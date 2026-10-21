/**
 * Materialize client-local `@file` mentions into real attachments when a
 * prompt is forwarded to the relay server (2.2.8).
 *
 * WHY: DSH's composer prefers a path reference over an upload whenever the
 * desktop shell can name a dropped file's absolute path (RT
 * dsh-client-ui-conversation `addFiles`: `hostPathBridge().pathFor(file)` —
 * a non-empty path becomes `@<path>` text). Locally that is correct. In a
 * REMOTE session the path is on the machine showing the UI while the agent
 * runs on the server, so the prompt arrives as unreadable text
 * (`@C:\Users\me\Desktop\日志.txt`) and the model never sees the file. The
 * same happens when a user types or pastes such a path by hand.
 *
 * WHAT: before forwarding `session/prompt`, scan the text parts for `@`
 * mentions that are ABSOLUTE paths existing as files on THIS machine. For
 * each one the server does not already have (a relayed `workspaceFiles/stat`
 * probe), upload the bytes through the relay's binary channel — the host
 * stages a receipt exactly as it does for a normal attachment — and replace
 * the mention text with a `{type:'file', receiptId}` content block. The
 * model then receives the file itself.
 *
 * The mention grammar mirrors `@path` / `@"path with spaces"` (the form
 * dsh-file-reference writes). Only absolute paths are considered: relative
 * mentions are workspace-relative and already resolve on the server. Every
 * failure is non-fatal — the prompt forwards untouched.
 *
 * Pure decision helpers (`fileMentionsIn`, `isAbsolutePathMention`) are
 * exported for tests; `materializeLocalFileMentions` takes the relay face so
 * tests can drive it with fakes.
 */
import { createReadStream } from 'node:fs';
import { stat } from 'node:fs/promises';
import { basename } from 'node:path';
import { Readable } from 'node:stream';
/** Uploads are bounded by the relay's own 100 MiB binary channel. */
const MAX_UPLOAD_BYTES = 100 * 1024 * 1024;
/** More than this many locales paths in one prompt is a paste accident, not intent. */
const MAX_MENTIONS = 8;
/** Absolute in either spelling the Host accepts: POSIX, Windows drive, UNC. */
export function isAbsolutePathMention(path) {
    return path.startsWith('/') || /^[A-Za-z]:[\\/]/u.test(path) || /^\\\\/u.test(path);
}
/**
 * Every absolute-path `@` mention in one text part, in order.
 *
 * A mention starts at `@` when the preceding character cannot be part of an
 * identifier (start of text, whitespace, an opening bracket, or common CJK
 * punctuation — `邮箱@example.com` must not become a path). The quoted form
 * `@"…"` ends at the closing quote; the bare form ends at whitespace. A
 * trailing `)`, `]`, `}` or `）` is trimmed because prose wraps paths in
 * them; a bare token with none of those follows.
 * @param text - one prompt text part.
 * @returns the mention ranges and their paths.
 */
export function fileMentionsIn(text) {
    const mentions = [];
    for (let index = 0; index < text.length; index += 1) {
        if (text[index] !== '@')
            continue;
        const previous = index === 0 ? '' : text[index - 1] ?? '';
        if (previous !== '' && !/[\s([{（【，。,:：;；!?]/u.test(previous))
            continue;
        if (text[index + 1] === '"') {
            const close = text.indexOf('"', index + 2);
            if (close === -1)
                continue;
            const path = text.slice(index + 2, close);
            if (isAbsolutePathMention(path))
                mentions.push({ start: index, end: close + 1, path });
            index = close;
            continue;
        }
        let cursor = index + 1;
        while (cursor < text.length && !/\s/u.test(text[cursor] ?? ''))
            cursor += 1;
        let path = text.slice(index + 1, cursor);
        while (path.length > 0 && /[)\]}）,、。；;：:!?！？]/u.test(path[path.length - 1] ?? '')) {
            path = path.slice(0, -1);
        }
        if (path.length > 0 && isAbsolutePathMention(path)) {
            mentions.push({ start: index, end: index + 1 + path.length, path });
        }
        index = cursor - 1;
    }
    return mentions;
}
/** True when the server already serves this path in the session's scope. */
async function hostHasPath(relay, sessionId, path, signal) {
    try {
        await relay.invoke('workspaceFiles', 'stat', { workspaceFileScopeId: sessionId, path }, signal);
        return true;
    }
    catch {
        return false;
    }
}
/** One local file's staged receipt, or undefined when it must stay text. */
async function stageLocalFile(relay, sessionId, path, signal) {
    let info;
    try {
        info = await stat(path);
    }
    catch {
        return undefined;
    }
    if (!info.isFile() || info.size > MAX_UPLOAD_BYTES)
        return undefined;
    if (await hostHasPath(relay, sessionId, path, signal))
        return undefined;
    try {
        const body = Readable.toWeb(createReadStream(path));
        const result = await relay.upload({ sessionId, name: basename(path), body, bytes: info.size }, signal);
        if (result.status !== 200)
            return undefined;
        const parsed = JSON.parse(result.body);
        if (typeof parsed !== 'object' || parsed === null)
            return undefined;
        const envelope = parsed;
        if (envelope.ok !== true || typeof envelope.value?.receiptId !== 'string')
            return undefined;
        return envelope.value.receiptId;
    }
    catch {
        return undefined;
    }
}
/**
 * Rewrite one forwarded prompt's locale-path mentions into file receipts.
 *
 * @param args - the invoke arguments (`{ request: { sessionId, content } }`);
 *   mutated in place only when at least one mention was staged.
 * @param relay - the relay face (host probe + binary upload).
 * @param signal - the call's cancellation.
 * @returns the same arguments object, possibly rewritten.
 */
export async function materializeLocalFileMentions(args, relay, signal) {
    if (typeof args !== 'object' || args === null)
        return args;
    const request = args.request;
    if (typeof request !== 'object' || request === null)
        return args;
    const scope = request;
    if (typeof scope.sessionId !== 'string' || !Array.isArray(scope.content))
        return args;
    const staged = [];
    const blocks = [];
    let changed = false;
    let stagedCount = 0;
    for (const raw of scope.content) {
        if (typeof raw !== 'object' || raw === null) {
            blocks.push(raw);
            continue;
        }
        const block = raw;
        if (block.type !== 'text' || typeof block.text !== 'string') {
            blocks.push(raw);
            continue;
        }
        const text = block.text;
        const mentions = fileMentionsIn(text);
        if (mentions.length === 0 || stagedCount >= MAX_MENTIONS) {
            blocks.push(raw);
            continue;
        }
        let next = text;
        for (let index = mentions.length - 1; index >= 0; index -= 1) {
            const mention = mentions[index];
            if (mention === undefined || stagedCount >= MAX_MENTIONS)
                continue;
            const receiptId = await stageLocalFile(relay, scope.sessionId, mention.path, signal);
            if (receiptId === undefined)
                continue;
            staged.unshift({ type: 'file', receiptId });
            stagedCount += 1;
            next = next.slice(0, mention.start) + next.slice(mention.end);
            changed = true;
        }
        blocks.push(next === text ? raw : { ...raw, text: next });
    }
    if (!changed)
        return args;
    scope.content = [...staged, ...blocks];
    return args;
}
//# sourceMappingURL=prompt-file-mentions.js.map
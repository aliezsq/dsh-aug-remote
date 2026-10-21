/** One `@path` occurrence in a text part. */
export interface FileMention {
    /** Offset of the leading `@`. */
    start: number;
    /** Offset just past the mention (exclusive). */
    end: number;
    /** The mention's path, quotes stripped. */
    path: string;
}
/** Absolute in either spelling the Host accepts: POSIX, Windows drive, UNC. */
export declare function isAbsolutePathMention(path: string): boolean;
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
export declare function fileMentionsIn(text: string): FileMention[];
/** The relay face this module needs (invoke for the host probe, upload for bytes). */
export interface MentionRelay {
    invoke(namespace: string, method: string, args: unknown, signal?: AbortSignal): Promise<unknown>;
    upload(options: {
        sessionId: string;
        name?: string;
        body: ReadableStream<Uint8Array> | null;
        bytes?: number;
    }, signal?: AbortSignal): Promise<{
        status: number;
        body: string;
    }>;
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
export declare function materializeLocalFileMentions(args: unknown, relay: MentionRelay, signal?: AbortSignal): Promise<unknown>;
//# sourceMappingURL=prompt-file-mentions.d.ts.map
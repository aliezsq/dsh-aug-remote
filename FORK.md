# Fork maintenance guide

This repository is a maintained fork of
[KyoMio/dsh-zen-remote](https://github.com/KyoMio/dsh-zen-remote). Upstream is
the source of truth for the plugin; this fork carries the changes listed in
[NOTICE](NOTICE).

## Branch layout

- `main` — this fork's release line (upstream tags + our commits).
- `upstream` remote — the original repo, used only for syncing.

```bash
git remote add upstream https://github.com/KyoMio/dsh-zen-remote.git  # once
git fetch upstream --tags
```

## Following a new upstream release

```bash
./scripts/sync-upstream.sh            # newest upstream tag
./scripts/sync-upstream.sh v2.2.7     # a specific tag
```

The script fetches tags, rebases `main` onto the tag, then reinstalls, builds
and type-checks. Conflicts usually land on the version lines of
`package.json` / the READMEs (we carry our own version line); resolve them,
keep OUR version, then:

```bash
pnpm build && pnpm verify && pnpm test
```

`pnpm test` has two socket-buffer-dependent cases that fail on some hosts even
on a stock checkout — treat only *new* failures as a problem.

## Release

```bash
# 1. bump (updates both README examples through the version script)
npm version patch --no-git-tag-version
# 2. rebuild the tracked lib/ and commit
pnpm build && git add -A && git commit -m "release: vX.Y.Z"
# 3. push the branch and the tag (CI builds/tests and attaches the tarball)
git push origin main
git tag vX.Y.Z && git push origin vX.Y.Z
```

The `release` workflow builds, checks that `lib/` matches `src/`, runs
`pnpm verify` and `pnpm test`, then attaches `dsh-zen-remote-<version>.tgz` to
the GitHub Release.

## Installing a release

- **Host** (`dsh web`, profile `web`):
  ```bash
  cd ~/.dsh/profiles/web/node_modules
  mv dsh-zen-remote dsh-zen-remote.bak
  mkdir dsh-zen-remote
  tar -xzf /path/to/dsh-zen-remote-X.Y.Z.tgz -C dsh-zen-remote --strip-components=1
  systemctl restart dsh-web
  ```
- **Windows desktop client**:
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\scripts\install-client.ps1 -Package .\dsh-zen-remote-X.Y.Z.tgz
  ```
  (quit the desktop app first; roll back with `rollback-client.ps1`).

Both ends must run the **same build**: the relay protocol and the access tables
are versioned together.

## Do not publish to npm as `dsh-zen-remote`

The npm name belongs to upstream. If this fork ever needs an npm package, use a
scope (e.g. `@yourscope/dsh-zen-remote`), update `package.json`, the
`cordis.patch.yml` insert name and the profile dependency together, and expect
the plugin's internal name strings (~90 references) to need a pass.

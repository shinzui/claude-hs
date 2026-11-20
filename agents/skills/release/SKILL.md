---
name: release
description: Release the claude-hs package to Hackage following PVP
argument-hint: "[major|minor|patch]"
disable-model-invocation: true
allowed-tools: Read, Bash, Edit, Glob, Grep, Write, AskUserQuestion
---

# claude-hs Release Skill

Release the `claude-hs` package from this repository to Hackage, tag the
release in git, and create a matching GitHub release.

## Versioning Strategy

This is a **single-package** repository. The version is in
`claude-hs.cabal` (`version:` field) and follows the Haskell PVP
(`A.B.C.D`). A single annotated git tag `v<version>` marks each release.

## Package

- **claude-hs**: `./claude-hs.cabal` at the repo root (`cabal.project` has
  `packages: .`). It contains:
  - `library`: the public API (`Claude.Batches`, `Claude.Client`,
    `Claude.Messages`, `Claude.Messages.Features`, `Claude.Streaming`)
  - `executable claude-message-example`: an example program in `example/`,
    shipped as a component of the same package
  - `test-suite claude-hs-test`: tests in `test/`

These are **not released** and are not Hackage packages:
- `integration/consumers/`: downstream consumer patches and qualification
  scripts (Baikai, Shikigami, Shikumi). No cabal file.
- `docs/`, `mori/`, `agents/`: project documentation, plans, and tooling.

## Arguments

`$ARGUMENTS` is optional:
- `major`, `minor`, or `patch` sets the bump level.
- If omitted, determine the bump level from the changes (see step 2).

## Steps

### 0. Preflight: Hackage readiness

Check these before anything else. If any of them fails, report it and ask the
user how to proceed. Do not paper over it yourself.

- `claude-hs.cabal` declares the metadata that `cabal check` and Hackage
  require: `license` (plus a `license-file` that exists, e.g. `LICENSE`),
  `author`, `maintainer`, `homepage`/`bug-reports`, and a
  `source-repository head` stanza pointing at
  `https://github.com/shinzui/claude-hs`. The initial scaffold had none of
  these. Ask the user for the license and maintainer details rather than
  guessing.
- `CHANGELOG.md` exists at the repo root and is listed in `extra-doc-files`
  (create it in step 3 if needed, and add it to `extra-doc-files`).
- The working tree is clean (`git status --porcelain`) and you are on
  `master`, up to date with `origin/master`.
- Hackage credentials are configured (`~/.config/cabal/config` or
  `CABAL_DIR` holds a `token`, or a username/password).
- The GitHub repo visibility (`gh repo view --json visibility`). If it is
  `PRIVATE`, warn the user: the `source-repository` link and the GitHub
  release will not be publicly reachable. Ask whether to make it public
  before publishing.

### 1. Determine what changed since the last release

- Read the current version from `claude-hs.cabal`.
- Find the latest tag with `git tag --list 'v*' --sort=-v:refname | head -1`.
- List commits since that tag with `git log --oneline <last-tag>..HEAD`. If
  there is no tag yet, this is the **first release**: use `git log --oneline`
  over the whole history.
- If the tag exists and there are no commits since it, tell the user there is
  nothing to release and stop.

Present a summary showing:
- Current version
- Last release tag (or "none, first release")
- Number of commits since the last release
- Which areas changed (`src/`, `example/`, `test/`, `claude-hs.cabal`,
  docs only, …), using `git diff --stat <last-tag>..HEAD`

### 2. Determine the next version using PVP

The Haskell PVP version format is `A.B.C.D`:
- `A.B` is the **major** version. Bump it for breaking API changes: removed or
  renamed exports, changed types, changed semantics, or changes to exposed
  modules.
- `C` is the **minor** version. Bump it for backwards-compatible API
  additions: new exports, new modules, new instances, new record fields
  behind smart constructors.
- `D` is the **patch** version. Bump it for bug fixes, documentation,
  internal-only changes (`Claude.Internal.*`, `Claude.Messages.Usage`, which
  are `other-modules`), and performance work.

Rules:
- **First release:** if there is no `v*` tag yet, propose releasing the
  current cabal version (`0.1.0.0`) unchanged, unless `$ARGUMENTS` says
  otherwise.
- If `$ARGUMENTS` is `major`, `minor`, or `patch`, use that bump level.
- Otherwise, infer the level from the Conventional Commits history:
  - `feat!:`, `BREAKING CHANGE:`, or removed/renamed exports in the diff of
    exposed modules → major
  - `feat:` → minor
  - `fix:`, `docs:`, `test:`, `refactor:`, `chore:`, `perf:` → patch
- Look at the diff of exposed modules under `src/Claude/` to confirm the
  level. Do not rely only on commit messages.
- Present the proposed version and your reasoning to the user and ask for
  confirmation before proceeding.

Increment the version:
- **major**: increment `B`, reset `C` and `D` to 0 (e.g. `0.1.2.3` → `0.2.0.0`)
- **minor**: increment `C`, reset `D` to 0 (e.g. `0.1.2.3` → `0.1.3.0`)
- **patch**: increment `D` (e.g. `0.1.2.3` → `0.1.2.4`)

### 3. Update the version and changelog

#### Version update
- Edit the `version:` field in `claude-hs.cabal`.
- The `example` and `test-suite` components depend on `claude-hs` without a
  bound (same package), so no internal bounds need updating.

#### Changelog update
- Update the root `CHANGELOG.md`. If it does not exist, create it with a
  `# Changelog` header and add `CHANGELOG.md` to `extra-doc-files` in
  `claude-hs.cabal`.
- Add a new section `## <version> (YYYY-MM-DD)` (today's date) above any
  previous entries.
- Move content from an `## Unreleased` section (if any) into the new section.
- Summarize commits since the last release, grouped by:
  - **Breaking Changes** (if major)
  - **New Features** (if minor or major)
  - **Bug Fixes** (if any)
  - **Other Changes** (docs, tests, refactoring, tooling)
  - Only include categories that have entries. Write user-facing entries in
    terms of the public `Claude.*` API, not internal plan numbers.

Show the user ALL changes (version bump, cabal metadata edits, changelog
entry) for review before committing.

### 4. Verify builds (mandatory gates)

Run these inside the dev shell (direnv loads it automatically, or prefix with
`nix develop -c`):

1. `nix fmt` to format the code (treefmt with fourmolu, per `fourmolu.yaml`).
2. `cabal build all` to build the library, example, and tests.
3. `cabal test all --test-show-details=direct` to make sure the test suite
   passes.
4. `cabal check` to check for Hackage packaging problems. It must report no
   errors.
5. `nix flake check` for treefmt, the pre-commit checks, and the
   `packages.default` (`claude-hs`) build.
   - Nix only sees files tracked by git, so `git add` new files (e.g. a new
     `CHANGELOG.md` or `LICENSE`) before running it.

If any gate fails, stop and fix the issue (or report it) before proceeding.
Re-run `nix fmt` after any fix.

### 5. Commit, tag, and push

Only after the user has approved the changes:

- Stage `claude-hs.cabal`, `CHANGELOG.md`, and any other files the release
  touched (e.g. `LICENSE`).
- Create a single Conventional Commits commit: `chore(release): <version>`.
  The body summarizes what's in the release and why this bump level was
  chosen.
- Create an annotated tag: `git tag -a v<version> -m "Release <version>"`.
- Push the commit and the tag: `git push origin master && git push origin v<version>`.

### 6. Publish to Hackage

From the repo root:

1. Run `cabal check` again on the committed tree.
2. Run `cabal sdist`. It prints the tarball path
   (`dist-newstyle/sdist/claude-hs-<version>.tar.gz`).
3. Optionally, before publishing, upload a candidate with `cabal upload <tarball>`
   (no `--publish`) and check the rendered page at
   `https://hackage.haskell.org/package/claude-hs-<version>/candidate`.
   Recommended for the first release.
4. Run `cabal upload --publish dist-newstyle/sdist/claude-hs-<version>.tar.gz`.
5. Build docs with `cabal haddock claude-hs --haddock-for-hackage --haddock-hyperlink-source --haddock-quickjump`.
6. Upload them with `cabal upload --publish --documentation dist-newstyle/claude-hs-<version>-docs.tar.gz`
   (use the docs tarball path that `cabal haddock` printed).
7. Report the Hackage URL: `https://hackage.haskell.org/package/claude-hs-<version>`.

### 7. Create GitHub release

After the Hackage upload succeeds:

```bash
gh release create v<version> --title "v<version>" --notes "$(cat <<'EOF'
## Hackage

https://hackage.haskell.org/package/claude-hs-<version>

## What's Changed

<changelog entries for this version from CHANGELOG.md>
EOF
)"
```

Report the GitHub release URL when done.

## Important

- Always ask the user to confirm the version and the changelog before
  committing.
- Never invent license, author, or maintainer metadata. Ask the user.
- Never skip the gates: `nix fmt`, `cabal build all`,
  `cabal test all`, `cabal check`, `nix flake check`.
- If any step fails, stop and report the error rather than continuing.
- If the Hackage source upload fails, do NOT upload docs or create the GitHub
  release. A pushed tag with no Hackage release must be reported to the user.
- Hackage uploads are irreversible (a version can be deprecated but never
  replaced). Re-confirm the version with the user right before
  `cabal upload --publish`.
- The commit and tag are created only AFTER the user approves all changes.
- Do not run this skill's steps for `integration/consumers/`. Those
  downstream patches are not part of the release.

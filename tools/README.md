# Building and publishing Slopcraft 2

`build_release.py` produces real Godot 4.7 packages, records their SHA256 hashes, and requires native macOS **and** Windows receipts before publication. A normal build never publishes a release or commits the launcher catalog.

## Repository layout

- `game/`: current snapshot project and source tests.
- `launcher/`: standalone launcher, its tests, and the public `manifest.json`.
- `archive/0.1/`: genuine historical 0.1 project, retaining its original gameplay and saves.
- `tools/build_release.py`: Python 3.11+ build, verification, catalog, and publication tool; standard library only.
- `.github/workflows/release.yml`: cross-export on `macos-14`, native verification on `windows-2022`, and explicitly gated publication on `ubuntu-24.04`.

The snapshot version is read from the first entry in `launcher/manifest.json`; give a new snapshot a new ID before publishing it. The historical build uses `0.1` and the immutable `archive-0.1` tag. There is no fabricated stable release.

## What the workflow does

Every branch push, pull request, and manual run builds and checks the projects. Each distribution contains four ZIPs:

| Product | macOS | Windows |
| --- | --- | --- |
| Game | Universal app, Apple silicon and Intel | x86_64 executable and resources |
| Launcher | Universal app, Apple silicon and Intel | x86_64 executable and resources |

The workflow builds the current snapshot distribution and, separately, the historical 0.1 distribution, for eight ZIPs in total. The 0.1 distribution includes the current launcher packaged alongside the original game.

The build job downloads official Godot binaries and export templates and verifies the SHA256 values pinned in `build_release.py`. It imports both projects, runs their `tests/test_*.gd` scripts, exports both products for both systems, verifies ZIP paths and executable layouts, and smoke-tests the macOS exports. The Windows job downloads those exact ZIPs and smoke-tests them on Windows; it does not rebuild them.

Current snapshot smoke checks include game and launcher startup, world startup, and the launcher's real installation/profile handoff test. The historical build uses `--game-smoke-mode legacy`: native game and launcher title startup plus the original world creation/save smoke are verified. The historical game predates launcher name/skin handoff; that newer profile test is applied only to the current snapshot. Logs are scanned for engine/script errors as well as process exit codes and success markers.

Each `verified-<platform>.json` binds its platform, version, source commit, required checks, and both product hashes to `build.json`. The Linux publication job verifies the ZIPs and both receipts again. Missing receipts, mismatched hashes, or receipts from another revision stop publication.

`macos-distributions` and `windows-verification` are retained as Actions artifacts for 14 days. Failed jobs retain their logs when available. The final publication job retains its own diagnostics.

## Explicit publication

Publication is allowed only in `SloppistGames/Slopcraft2`, from `main`, after both native jobs succeed, with either:

1. **Actions → Build, verify and publish → Run workflow**, selecting `main` and setting **publish** to `true`; or
2. A push to `main` whose **head commit message** contains the exact marker `[publish]`.

Manual runs default to `publish: false`. Ordinary pushes, pull requests, and manual runs from other branches only build and check. Event text is evaluated in the job condition; it is never interpolated into a shell command.

The publish job alone receives `contents: write`. GitHub supplies `GITHUB_TOKEN`, exposed to the release tool as `GH_TOKEN`; local `gh auth login` is unnecessary in Actions. Repository settings and branch protections must permit this workflow token to create releases and push the catalog commit to `main`. If policy prohibits direct bot commits, the release assets can succeed while the final catalog push fails; a maintainer must review and commit the generated catalog. The workflow never force-pushes or bypasses protection.

The workflow verifies that `main` still matches the tested commit before publishing. It publishes **archive first, snapshot second**, then merges both verified catalog entries into `launcher/manifest.json`, promotes the current snapshot to the first position, and preserves all other versions and catalog fields. Only after both releases succeed does it commit that file with `[skip ci]`. It checks the branch tip again before committing so unrelated newer commits are never overwritten.

Releases are immutable:

- An existing 0.1 archive is downloaded with all four ZIPs, metadata, and native receipts, verified again, and reused. Its assets and checksums are never replaced by a later rebuild.
- A published snapshot can be reused for recovery only when its source commit is the same tested commit and its downloaded artifacts and receipts verify. A tag from another commit requires a new version ID.
- An existing draft stops the workflow. Inspect its logs and uploaded assets before completing or removing that draft manually. No automatic deletion of releases or replacement of assets occurs.
- If `main` advances during release upload, the assets remain published but the catalog update stops for review. Use the verified release metadata to repair the catalog; do not overwrite an immutable release to work around a branch race.

The tool creates a draft, uploads ZIPs and verification files, and only then makes the release public. A failed upload can leave a draft, which is intentionally visible for investigation.

## Local macOS build

Run from the repository root with Python 3.11+ and enough disk space for Godot templates, two distributions, and temporary exports:

```sh
GODOT_ENGINE="$(python3 tools/build_release.py bootstrap --templates)"
python3 tools/build_release.py build --godot "$GODOT_ENGINE" --output dist/snapshot \
  --game-path game --launcher-path launcher --category snapshot --game-smoke-mode world
python3 tools/build_release.py build --godot "$GODOT_ENGINE" --output dist/archive \
  --game-path archive/0.1 --launcher-path launcher --version 0.1 \
  --category archive --tag archive-0.1 --title "Original 0.1 archive" --game-smoke-mode legacy
```

The tool uses the checkout's full Git commit SHA unless `--source-sha` is explicitly supplied. Do not claim a dirty working tree corresponds to an unrelated clean commit. An existing correct Godot 4.7 executable can be passed with `--godot` when the matching export templates are already installed.

## Native Windows verification

Transfer both complete `dist/snapshot` and `dist/archive` directories to a Windows checkout of the same source revision. In PowerShell:

```powershell
$GodotEngine = python tools/build_release.py bootstrap
python tools/build_release.py smoke --root . --godot "$GodotEngine" --dist dist/snapshot --platform windows
if ($LASTEXITCODE -ne 0) { throw "Snapshot smoke failed" }
python tools/build_release.py smoke --root . --godot "$GodotEngine" --dist dist/archive --platform windows
if ($LASTEXITCODE -ne 0) { throw "Archive smoke failed" }
```

Copy the resulting Windows receipts back alongside each distribution's original macOS receipt. On any system with Python:

```sh
python3 tools/build_release.py verify --dist dist/archive
python3 tools/build_release.py verify --dist dist/snapshot
```

These commands validate evidence; they do not substitute for native execution.

## Manual publication and catalog preparation

Prefer the gated Actions workflow. For an authorized local publication, install GitHub CLI, supply `GH_TOKEN` through the environment, and run after both distributions verify:

```sh
python3 tools/build_release.py publish --dist dist/archive
python3 tools/build_release.py publish --dist dist/snapshot
python3 tools/build_release.py catalog --base launcher/manifest.json --dist dist/archive --output dist/catalog-with-archive.json
python3 tools/build_release.py catalog --base dist/catalog-with-archive.json --dist dist/snapshot --output dist/catalog-final.json
```

The standalone `publish` command refuses every existing tag; the workflow adds the verified reuse/recovery behavior described above. `catalog` replaces an existing version in place, so review the final ordering and place the current snapshot first before committing it. Review `dist/catalog-final.json`, then update `launcher/manifest.json` only after both releases are public. Do not add fictional package URLs, platform claims, or checksums.

## Pinned Actions and toolchain maintenance

Official action tags were resolved with `git ls-remote` against their upstream repositories on 2026-11-02. The workflow uses the full commit SHAs, not mutable tags:

| Action | Audited tag | Commit |
| --- | --- | --- |
| [actions/checkout](https://github.com/actions/checkout) | v4.4.0 | `11d5960a326750d5838078e36cf38b85af677262` |
| [actions/setup-python](https://github.com/actions/setup-python) | v5.6.0 | `a26af69be951a213d495a4c3e4e4022e16d87065` |
| [actions/upload-artifact](https://github.com/actions/upload-artifact) | v4.6.2 | `ea165f8d65b6e75b540449e92b4886f43607fa02` |
| [actions/download-artifact](https://github.com/actions/download-artifact) | v4.3.0 | `d3f86a106a0bac45b974a628896c90dbdf5c8093` |

To update a pin, resolve the intended version from its official repository, inspect the upstream change, and update both the workflow and this table. Godot updates require new official download hashes and matching export-template checks in `build_release.py`, followed by native smoke tests on both operating systems.

macOS exports are ad-hoc signed and **not notarized**; Windows exports are **unsigned**. This pipeline does not provide signing credentials or claim trusted distribution. Windows checks require a real Windows runner; exporting a PE file on macOS alone does not satisfy them.

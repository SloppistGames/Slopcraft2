# Slopcraft 2

A voxel survival sandbox and standalone version launcher, built with Godot 4.7 and GDScript.

[Download published versions](https://github.com/SloppistGames/Slopcraft2/releases) · [Snapshot notes](game/RELEASE_NOTES.md) · [Known limitations](game/docs/known-limitations.md) · [Build and release instructions](tools/README.md)

## Play

Download a **Slopcraft2Launcher** package for your platform from a published release, extract it, and open the launcher. Choose a version, install it, and press Play. The launcher checks for new versions on startup, when it regains focus, and every five minutes. Installed versions remain available offline. Choose “Latest available” to follow new releases, or select a specific version to keep it pinned.

Game packages are also available separately. macOS packages support Apple silicon and Intel; Windows packages target x86_64. The macOS bundles are ad-hoc signed and are not notarized; Windows executables are unsigned. No account or GitHub token is required to download public releases.

Worlds are stored separately from installed program files. Removing an installed version retains its data. Use the in-game world export/import controls for portable backups. Keep backups when moving worlds between versions; older code cannot read every newer save format.

## Develop

Open `game/project.godot` or `launcher/project.godot` with Godot 4.7. The game preserves the requested `world`, `blocks`, `player`, `inventory`, `entities`, `rendering`, `saving`, and `ui` modules, with shared gameplay systems in `systems`.

Snapshot 0.5.0f expands terrain, weather, pixel art, shaped blocks, fluids, circuits, creatures, beds, boats, the world atlas, controls, music and skin handoff. It is a development snapshot with bounded systems, not a claim of complete Minecraft feature parity. The documentation lists the practical limits.

The `archive/0.1` directory contains genuine preserved pre-update source, rebuilt as an archive release. Historical behavior and saves are retained; launcher profile/skin arguments were introduced later and are not retrofitted into 0.1.

## Release integrity

The workflow exports both game and launcher packages for macOS and Windows, verifies native execution on both operating systems, and publishes only after both checks pass. Published version assets are immutable. The launcher catalog contains the exact download URLs, SHA-256 checksums and executable paths. A normal push runs checks; publication requires an explicit workflow dispatch or a main-branch commit marked `[publish]`.

Original pixel artwork is generated from GDScript; the supplied logo and “Slopwoofer Lullaby” track are included as game assets. The bundled pixel font's license is in `game/assets/FONT-LICENSE.txt`.

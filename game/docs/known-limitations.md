# Snapshot 0.5.0f — Known limitations and delivery status

This file distinguishes implementation scope from package verification and publication. Use each release's build record and platform receipts to identify the exact source and binaries tested; passing source-level tests alone does not establish a published release.

## Package verification and publication

The delivery requirement is actual Windows and macOS game builds for each published version, plus launcher packages for both systems. Export presets or a version-list entry are insufficient evidence.

| Deliverable | Current verified status |
| --- | --- |
| Snapshot 0.5.0f macOS game | Exported; universal binary, signature, title, and world smoke checks passed locally |
| Snapshot 0.5.0f Windows game | Exported; Windows runtime verification gate pending |
| macOS launcher | Exported; startup and actual game-package installation/profile handoff passed locally |
| Windows launcher | Exported; Windows installation/launch verification gate pending |
| Historical 0.1 game | Source provenance verified; distribution must use its separate build record and platform receipts |
| Stable release | None established; do not relabel a snapshot or archive as stable |

All four snapshot game/launcher packages are actual exports. The CI build record includes the tested source commit and each package's SHA-256, size, and executable path. The matching macOS receipt covers game title/world startup, launcher startup, and actual package installation. The installation/profile test passed 11 checks, including player-name forwarding, the exact skin hash, and an isolated version-specific world directory. A universal binary includes both architectures; native execution on every supported Mac architecture has not been established by that fact alone.

macOS packages are ad-hoc signed without notarization; Windows packages are unsigned. Windows CI runtime verification and public asset publication remain pending. Prepared catalog entries and download URLs are build metadata, not evidence that those URLs are live. Automatic catalog discovery is tested, but it can offer a downloadable version only after verified assets are published.

Each published version must carry `build.json` with its source commit and package hashes, plus matching macOS and Windows verification receipts. Receipt hashes must match the distributed files. Rebuilt files require new hashes and package verification. No Windows runtime result or public download availability is claimed until those gates pass.

## Historical version provenance

The preserved `work/snapshot050/pre-update-source.zip` contains 69 entries and is 70,487,340 bytes. Its SHA-256 is:

`7ae40d2b7a140a81eaca0b14b90424afa38851d757eba589260292007740ad55`

The archive's `Slopcraft2/game.gd` declares `0.1 • THE THREE REALMS`. It contains `project.godot`, `main.tscn`, 22 GDScript files, assets, tests, and export presets for universal macOS and Windows x86_64. The project selects Godot 4.7 and GL Compatibility. ZIP integrity passed. A static resource-reference scan found no missing runtime assets or native-extension dependency; screenshot-output paths are external developer artifacts.

This is genuine preserved 0.1 source for rebuilding both platforms. Its provenance does not certify any particular historical package: use the archive release's own build record and platform receipts for that evidence. The included original `Slopcraft 2.dmg` is 71,863,676 bytes; its internal version and runtime were not verified by the source-provenance audit. A matching filename elsewhere is not evidence of a 0.5.0f build. Publish 0.1 only after building and testing its own source, and distinguish a newly rebuilt archive from an original released binary. No other historical versions have been established by this audit.

## Generation and world scale

New-generation Overworld terrain spans Y=-176 through Y=191. Older worlds keep the legacy generator, height range, and existing gateway behavior. Their unexplored chunks do not automatically acquire the new biome/depth/structure system. The Nether and End retain their existing terrain generators.

The biome test sampled 63,001 columns for one large region/seed and found all requested surface biomes. Reproducibility and chunk-boundary checks cover representative regions, not every possible seed. Rivers and lakes are shaped procedural terrain, not a continent-scale erosion or drainage simulation. Structure layouts use a finite set of procedural templates; terrain-fit tests do not guarantee every distant placement is ideal. Tight caves do not add a dedicated crawling movement mode.

The 32-chunk setting is landscape visibility with distant terrain meshes. Detailed blocks have a separate 2–12 chunk setting; collision and active systems remain concentrated around the player. Distant terrain does not offer the same geometry, cave detail, collision, or live simulation as nearby chunks. Incremental work budgets reduce stalls but do not establish a frame-rate guarantee. High block distances, rapid travel, dense circuits, and severe weather still need sustained hardware profiling on both platforms.

## Environment and simulation scope

Weather is a climate-conditioned state with bounded precipitation around the camera. It is not a persistent world-wide map of moving storm fronts. Lightning supplies visual/audio effects; storms do not destroy builds. Snowfall does not accumulate new snow blocks. Forest drift is visual; seasonal tree shedding/regrowth is not implemented as a biological simulation.

Sulfur exposure, poison, mask protection, fog, and ambience are integrated. The gas is a cave-region hazard, not a gas-volume diffusion model, and the environmental effect does not include a separate simulated gas-particle cloud.

Water/lava updates and redstone operate within an approximately 80-block player neighborhood and bounded queues. Natural liquid sources remain stable until disturbed. Fluids are finite-distance cellular flows, not volume-conserving water physics. Waterlogging and arbitrary partial-block fluid volumes are not implemented.

Redstone uses Slopcraft's own scheduled rules. Pistons use cardinal horizontal orientation and a bounded push chain; some blocks are deliberately immovable. Dispensers have a limited set of item-specific actions. Do not assume Minecraft timing quirks, quasi-connectivity, every dispenser behavior, or arbitrary imported contraptions are supported. More complex circuits need individual testing.

Stairs use oriented shared shapes; automatic inner/outer stair corner joining is not claimed. Torch light counts and ranges are bounded for performance. There is no claim of a complete Minecraft lighting or block-state implementation.

## Creatures, villages, and transport

Mob navigation uses local heading/obstacle probes rather than global pathfinding. Initial fauna and discovered village inhabitants are supported; a broad ecosystem spawning/despawning system is not claimed. Profession trade stock persists and is finite; there is no restock schedule. Creature-specific animation exists, but there is not a complete animation-state matrix for every creature and action.

Beds require an intact supported pair, headroom, and a safe neighboring spawn position. Missing or blocked beds fall back to world spawn. Sleeping is limited to the Overworld. Boats use voxel hull/rider sweeps rather than rigid-body vessel physics; they are single-rider transport and have no passenger, cargo, or damage system. Saved-boat restoration is bounded to 128 boats.

## Saves, UI, and remaining acceptance work

Schema-2 saves preserve legacy generation selection and use atomic replacement/backups. Save limits include 32 MB per file and 250,000 block edits. Version-specific launcher data directories reduce accidental cross-version reuse; they do not make newer saves compatible with older game code. Keep an exported backup before moving a world between versions.

The world atlas is a surface overview with discovered areas and up to 128 waypoints. It is not a cave map, route planner, or live entity tracker. Native UI checks cover Save & Quit, reopening, and waypoint persistence; Windows UI behavior still requires its platform verification. The console intentionally supports only implemented commands: `/effect` currently provides healing, `/summon` is limited to pigs/sheep/slimes, coordinates are absolute, and `/fill` is capped at 4,096 blocks.

The frozen source run passed 19 game suites and 3 launcher suites. This includes the 40-check bed UV/orientation correction, 49 bed/boat checks, and 15 automatic-catalog checks. Native macOS package startup and launcher name/skin handoff also passed; details are in [release notes](../RELEASE_NOTES.md). These checks are bounded: they do not certify long-duration survival progression, every portal/terrain configuration, low-memory behavior, maximum-distance performance, or Windows runtime behavior. The remaining release gates are Windows verification and publication of the exact verified assets with matching receipts.

This snapshot adds working systems with bounded scope. It does not claim full Minecraft feature parity or that every request in the original brief has been exhaustively completed and verified.

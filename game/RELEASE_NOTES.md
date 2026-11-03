# Slopcraft 2 — Snapshot 0.5.0f

This is a development snapshot, not a stable release. Game and launcher packages have been exported for macOS and Windows. The frozen source test run and local macOS package verification passed. Windows runtime verification and public release publication remain gated; an exported file or prepared download URL does not establish that a release is publicly available.

## World generation and biomes

New worlds use a seeded terrain generator combining continentalness, erosion, temperature, humidity, elevation, rivers, and mountain ridges. Terrain blends across chunk boundaries, with coastal beaches, inland ponds, broad mountain regions, and climate-dependent surface materials. The sampled terrain reaches Y=160; sea level is Y=23, bedrock is Y=-176, and the stone-to-deepslate transition is centered near Y=-76.

All 26 requested surface biomes are reachable: Plains, Oak Forest, Sparse Spruce Forest, Dense Spruce Forest, Birch Forest, Mixed Forest, Permafrost, Temperate Highlands, Frozen Highlands, Mountain Ranges, Desert, Savanna, Swamp, Meadow, Taiga, Snowy Taiga, Snowy Forest, Rocky Badlands, Tundra, Alpine Peaks, Jagged Frozen Peaks, Coastal Cliffs, Beaches, River Valleys, Flower Fields, and Old-Growth Forests. Oceans provide additional regional terrain. Vegetation uses different species, spacing, heights, and canopies; generation tests check rooted trunks and connected leaves.

Normal, interconnected, tight, vast, and sulfuric caves use different underground shapes and depth distributions. Deepslate ores and sulfur resources are integrated. Existing worlds retain their legacy generator rather than having their terrain silently replaced; create a new world to explore the new generation.

## Weather, nature, and graphics

Climate-dependent weather includes clear, cloudy, overcast, light/moderate/heavy rain, thunderstorms, light/heavy snow, blizzards, windstorms, tropical storms, and hurricanes. Gradual transitions combine precipitation, wind, fog, lighting, and audio. Roof checks shelter precipitation, and severe weather does not destroy builds.

Lighting and exposure have been adjusted, with a persistent brightness setting. Landscape distance reaches 32 chunks using distant terrain meshes; a separate block-loading distance controls detailed terrain. Camera-position water/lava immersion adds tint, reduced visibility, distortion, and audio filtering. Sulfuric caves have gas-colored fog and ambience.

Leaves and plants sway with weather-driven wind. Forests have drifting leaf particles, and unsupported natural leaves decay through a budgeted support-check queue. Player-placed decorative leaves remain persistent.

## Blocks, items, and survival

Deepslate building variants and ores, sulfur materials, vegetation, farmland, paths, and circuit components join the existing registry. Building-material stair/slab families share oriented geometry, collision, selection, recipes, and saved block states. Top/bottom slabs can be combined where supported. Torches use narrow floor/wall models, flames, and nearby warm lights.

The craftable head-slot Gas Mask provides sulfur-gas protection, a wearable model, and a first-person mask overlay. Unprotected exposure poisons the player and changes the heart display; equipping the mask or leaving the gas ends that exposure.

Two-block beds set a validated respawn point and advance nighttime to morning in the Overworld. Removing either half removes its partner; losing support returns one bed, including deferred recovery when the inventory is full. Boats launch on water, carry the player, steer and float, stop against terrain or insufficient rider clearance, and save their position and mounted state. Right-click to board; use movement controls to row/steer and crouch to dismount.

Bed artwork now keeps the pillow at the head end, joins the blanket correctly between both halves, and maps the sides consistently in all four rotations. Dedicated bed-art checks and the bed/boat gameplay regressions pass after this correction.

Water and lava use scheduled voxel updates, with source/flow distinctions, downward flow, finite lateral spread, saved states, and water/lava interaction. Undisturbed natural sources sleep until nearby edits wake them.

## Creatures, structures, and progression

Pigs, sheep, slimes, villagers, and Enderslop use textured models and articulated animation. Creature checks cover obstacle probes, water movement, lava avoidance, dormancy, death persistence, and the existing boss/crystal encounter. Villager professions have distinct offers, persistent stock usage, and transactional trades that reject insufficient inventory space.

Seeded structures include villages, abandoned temples, mineshafts, strongholds, ruins, camps, underground ruins, and mountain cabins. Villages contain homes, paths, a farm, storage, lighting, and profession spawn markers. Structure loot initializes on first access and then uses saved container contents.

New-generation worlds do not place ready-to-use Nether or End gates. Build and ignite a valid obsidian frame for Nether travel. Craft and throw Eyes of Ender to find a stronghold, then fill all 12 End frames to activate its portal. Portal tests cover both Nether orientations, broken frames, return links, saved state, and real negative-depth stronghold queries.

## Redstone

Scheduled circuit updates connect dust and attenuate its signal. Functional components include switches, buttons, pressure plates, redstone torches/blocks, delayed repeaters, comparators, lamps, pistons/sticky pistons, observers, droppers, dispensers, and hoppers. Container hooks provide item transfer and comparator fill input. These are Slopcraft circuit rules; compatibility with arbitrary Minecraft contraptions is not promised.

## Interface, controls, and saving

F5 cycles first-person, rear third-person, and front third-person views. Camera collision and true-eye interactions are shared across views. Held items attach to the player arm, and compatible 64×64 custom skins apply to the actual model.

The command console opens with `/`, supports history and completion, validates arguments, and restricts modifying commands to Creative or cheats-enabled worlds. F6 quick-saves. Save & Quit captures world edits, block states, player equipment/appearance, entities, weather, portals, and system state before leaving. Save schema 2 retains legacy generator selection and uses atomic replacement with a backup.

Additional controls include the M world atlas with discovery and waypoints, configurable key/mouse bindings, and separate music volume/frequency settings for the supplied “Slopwoofer Lullaby” track. Game shutdown drains pending audio playback before exiting, including rapid start/stop sequences. Native UI checks cover Save & Quit, reopening a world, and saved waypoints.

## Launcher

A separate Godot launcher project provides version/category views, changelog display, local player names, launch preferences, and a skin editor with pencil, eraser, fill, palette, grid, zoom, undo/redo, PNG import/export, and a rotating model preview. The game and launcher share the player skin layout.

The installer supports manifest-selected packages, SHA-256 checks, safe extraction, separate installations and game-data directories, and launching a separate process. It refreshes the version catalog automatically while keeping installed versions available offline. Catalog-update tests cover the update behavior; public download availability depends on publication of verified packages.

Local macOS verification now installs the actual exported game through the launcher and checks the launched player name, exact skin hash, and version-specific world directory. No stable release or downloadable historical binary is invented.

## Verification evidence

The frozen build ran all 19 game suites and all 3 launcher suites successfully with Godot 4.7 on macOS. The build record identifies its source commit and the SHA-256 of each of the four exported packages. Counts below represent assertions, not hours of playtesting.

| Suite | Recorded result |
| --- | --- |
| Terrain | 23,774 checks, 0 failures; all 26 requested biomes sampled |
| Structures and portals | 81,389 checks, 0 failures |
| Beds and boats | 49 checks, 0 failures |
| Bed artwork and orientation | 40 checks, 0 failures |
| New-feature integration | 38 checks, 0 failures; clean music shutdown log |
| Content registry | 1,283 checks, 0 failures |
| Player snapshot | 149 checks, 0 failures |
| Entity snapshot | 124 checks, 0 failures |
| Core gameplay | 32 checks, 0 failures |
| Shapes | 2,261 checks, 0 failures |
| Pixel art | Pass; 317 blocks and 83 authored items checked |
| Redstone | 63 checks, 0 failures |
| World streaming | 349 checks, 0 failures |
| Weather and immersion | 96 checks, 0 failures |
| Nature | 17 checks, 0 failures |
| Fluids | 12 checks, 0 failures |
| General integration | 25 checks, pass |
| Snapshot save | Pass |
| Save/data validation | Pass |
| Launcher skin editor | 40 checks, 0 failures |
| Launcher installer | 28 checks, 0 failures |
| Automatic catalog updates | 15 checks, 0 failures |
| Actual macOS package installation/profile handoff | 11 checks, 0 failures |
| Native snapshot UI | 0 failures; Save & Quit, reopen, and waypoint persistence |

The exported macOS game and launcher passed universal-binary and code-signature checks, title startup, and game-world startup. The macOS receipt records the exact package hashes tested. Native creature, held-item, and bed/circuit galleries supplement these checks. These results do not establish Windows runtime success or performance equivalence across hardware.

Published releases must carry a source commit, package hashes, and matching macOS/Windows verification receipts. Windows CI verification and public asset availability remain pending for this delivery. See [known limitations and delivery status](docs/known-limitations.md) for scope, distribution gates, and historical-source provenance.

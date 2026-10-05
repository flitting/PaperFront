# Native performance kernels

Visual restoration update (2026-10-03): gameplay now always submits complete
authored meshes, pigment, borders and model animation. The native world lifecycle,
culling and batch upload remain enabled; the simplified native performance pose
path is retained for historical diagnostics but no longer selected by gameplay.
The old performance scores below refer to the earlier visual configuration; see
`docs/visual_fidelity_restoration.md` for current scope and validation.

The authoritative simulation stays in `scripts/simulation.gd`. `PaperFrontKernels` accelerates exact nearest-target queries, tick-local spatial indexes, weapon-domain checks, repair accounting and performance-tier model poses. It does not change clocks, update frequency, entity counts or combat rules. GDScript implementations remain available with `PAPER_FRONT_DISABLE_NATIVE=1` for comparison.

Build from the repository root:

```sh
./tools/build_native.sh
```

Requires CMake, a C++17 compiler, Make and Python 3. The vendored MIT Godot C++ bindings are pinned to `e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77` (Godot 4.5 API, tested with the installed Godot 4.6.2). No download is needed to rebuild. Compiler options intentionally exclude fast-math and fused contraction so target-distance ties retain the script result. The library is currently built and tested only for Linux x86_64.

`native/build/` and `native/vendor/` are excluded from Godot import using `.gdignore`; the runtime extension lives under `assets/native/`. When exporting, Godot copies `libpaper_front_kernels.so` beside the executable. Distribute that sidecar and the binding license with the executable. The current distribution is `artifacts/linux/`; see its manifest and `BUILD.sha256` for the exact visual-restoration build, which supersedes the earlier performance build.

Validation scripts:

- `tests/native_nearest_tests.gd`: actual native/script index, target, ownership, domain, transport and forced-target comparisons. Fails explicitly if the native class was not loaded.
- `tests/support_repair_equivalence_tests.gd`: exact health and money comparison against the original repair scan, including insufficient funds and eight owners.
- `tests/native_volume_tests.gd`: four-faction pose, transform, cargo, aircraft height, capture and cached-submission comparisons.
- `tools/profile_final_pressure_cpu.gd`: fixed 800-unit, eight-owner real simulation with reserve costs separated. This is a CPU diagnostic, not an FPS acceptance result.

Only run one GPU benchmark at a time. Do not compile or run other CPU-heavy tests concurrently with a GPU benchmark. The measured default rendering mode remains Safe; the separate rendering thread experiment produced engine errors and is not enabled in project settings.


Batched world geometry uses `scripts/pose_mesh.gd` for its CPU transform hierarchy and mesh references. It creates no redundant render instance; the MultiMesh remains responsible for drawing. Standalone models and Wiki previews keep real MeshInstance3D nodes. `PAPER_FRONT_RENDER_NODES=1` selects the old hidden render-node hierarchy for controlled comparisons. `tests/pose_mesh_tests.gd` checks mesh/pose/muzzle/particle equivalence; the four-faction frozen screenshot comparison is pixel-identical in the recorded capture.


The common unit state machine can now execute in the native kernel. It retains insertion-order tick processing and the original navigation, production, air service, special-command and damage-settlement methods. `PAPER_FRONT_SCRIPT_UNITS=1` restores the GDScript state machine; `PAPER_FRONT_SCRIPT_GEOMETRY=1` restores script collision queries; `PAPER_FRONT_SCRIPT_WORLD=1` restores the script world iteration. The full native/script unit comparison includes all factions, all unit definitions, live combat and a save/reload checkpoint. Renderer records cache stable node/resource references without owning their containing model Dictionary, so they do not form reference cycles.


Additional validation now includes `native_unit_tick_tests.gd` (whole authoritative tick and save/load equivalence), `native_geometry_tests.gd` (terrain/footprint/dynamic occupancy queries), `native_world_sync_tests.gd` (whole visual reader comparisons), and `unit_lod_provenance_tests.gd` (all four factions and eight owner palettes plus stale-resource fallback). All are included in `tools/test.sh`. The final full regression and the specified 1080p normal/stress performance gates passed. Native fullscreen is reported separately; see `docs/performance_640_results.md` for exact scope, tail latency, build identity and margins.


The pinned binding generator has a local patch in `native/patches/container-assignment.patch`: Dictionary move assignment previously copied into initialized storage without releasing its old reference; copy and move self-assignment also need guards. Rebuilding generates the fixed operators. The patched generator and patch are part of the performance manifest. `native_lifetime_tests.gd` verifies release and self-assignment reference counts, and native world tests must exit without resource/RID leak diagnostics. Native world iteration no longer constructs costly per-model visual-signature/replay arrays; unchanged GPU matrix uploads are still skipped by the batch uploader.


Current native additions include exact ground movement, per-tick definition views,
renderer model/pose caches, and `PaperFrontRenderBatch` ordered queues. Batch
capacity initialization establishes the engine CPU cache before bulk updates to
avoid synchronous GPU readback when sparse and bulk paths alternate. The public
model map remains usable by tools; cache reset/setup, external removals, resource
lifetime, insertion-order retirement and script transitions have regression tests.

`PAPER_FRONT_SCRIPT_MOVEMENT=1` selects reference ground movement;
`PAPER_FRONT_SCRIPT_BATCHES=1` selects script batches;
`PAPER_FRONT_BATCH_SETTERS=1` disables whole-buffer uploads;
`PAPER_FRONT_RENDER_OVERLAP=0` selects serial simulation/render scheduling;
`PAPER_FRONT_FULL_TRUNK_INK=1` restores full distant trunk ink geometry.
These switches are diagnostic comparisons, not the measured defaults.

Run `tools/test.sh` after rebuilding. It treats Godot script/engine errors and
leak diagnostics as failures even when the process returns exit code zero.

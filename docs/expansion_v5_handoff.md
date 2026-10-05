# Four-stage expansion handoff — 2026-10-04

All four implementation stages have passed the complete regression suite and the Linux Shipping runtime check. This is the final maintenance handoff; there is no remaining feature implementation. The directory is not a Git checkout.

## Accepted scope

- Six 320×320 battlefields, 2–4 local participants: human slot 0 plus configurable AI opponents.
- Air transports can land on legal open ground. Airports provide paid repair and replenishment.
- Economic equality is measured under equal deployed miner counts, routes and mining conditions.
- The creator hand is limited to one live or reserved unit per player and can be rebuilt after death.

## Modules and contracts

- `tech_availability.gd`, `building_construction.gd`: permanently visible locked catalog and independent normal/defense orders, with legacy save migration.
- `unit_transport.gd`, `transport_commands.gd`, `aircraft_operations.gd`: all ground infantry boarding, L landing, U designated unloading and B airport service. Aircraft apron reservations use physical visual clearance.
- `wall_connections.gd`, `selection_paths.gd`: connected detailed walls and selected friendly units’ remaining routes.
- `faction_traits.gd`, `faction_trait_text.gd`, `tools/faction_balance.py`: centralized incoming damage, four faction mechanics, matching UI text, shared miner parameters and refinery HP1600. Native and script paths use the same rules.
- `battlefield_catalog.gd`, `competitive_layout.gd`, environment modules: forest/desert/snow/city/random_city/islands, protected starts and expansion routes, 49 environment resources.
- `naval_navigation.gd`, `naval_operations.gd`, `naval_models.gd`: water-only routes, real surface height, boat boarding/unloading and shipyard construction. Naval IDs are `*_ship_transport/frigate/signature`. `iron_transport` remains the original ground APC.
- `match_config.gd`, `ai_controller.gd`, `team_vision.gd`: legal paid AI actions, difficulty decisions, shared sight and last-known records. New battlefields enable fog; legacy development fixtures preserve their existing defaults.
- `creator_hand_models.gd`, `hero_rules.gd`, `unique_unit_rules.gd`: five articulated fingers, two-finger walking, no wrist/forearm; $15000, HP20000, 0.5-second windup and one-hit building execution. Live plus queued limit one. Combat approach accounts for collision and movement tolerance.
- `campaign_map.gd`, `campaign_controller.gd`, `campaign_ui.gd`: one independent 320 Kestrel tutorial, seven real-action objectives, limited paid Rivet pressure. The live property is `sim.campaign_controller`; the save key is `campaign`.

Base and merge catalog generation both reapply balance, navy and creator extensions. Export presets include faction trait JSON. Preserve immutable mesh caches and per-instance hand joints. Runtime uses full authored models; baked LOD metadata does not reduce authored detail.

## Verified evidence

- `artifacts/expansion_v5/final_regression.result`: PASS; full log includes native threaded/main-thread unit dispatch, save validation and all feature suites.
- Real creator mouse input: native and script render paths each22 checks PASS. Model668 checks and main-world9 checks PASS.
- Campaign AI-on real paid playthrough:30 checks PASS,701 simulated seconds, two pressure waves, maximum four enemy armed units and nonnegative funds.
- Source and Linux Shipping main-scene checks: each88 checks PASS. Shipping is release mode with native simulation, render batches and world synchronization active.
- `artifacts/expansion_v5/runtime/runtime_report.md`: actual GPU conditions and reports. Forest48.61/city52.46/islands79.07 average FPS at1920×1080 with128 initial units and33–38 visible models. These are source measurements for the documented fixture.
- Runtime source identity: `d8e7b409f5dd15454762387e25a398d3c67e18f0ac250869fe2e2ff1b163046a`.

## Delivery

The Shipping staging files are `artifacts/expansion_v5/runtime_export/`. The final runnable path is `artifacts/linux/PaperFront.x86_64` and final archive is `artifacts/PaperFront-linux-x86_64.tar.gz`. See `docs/expansion_v5_validation.md` for their final synchronization, checksums and extraction verification. Repackage already validated exports with `tools/package_expansion_release.py`; do not treat copying/archiving as runtime validation.

Godot4.6.2 is available at `/usr/local/bin/godot`; actual GPU runs use Vulkan/Intel Arc and DISPLAY=:0. All new feature tests are integrated into `tools/test.sh`, except display-dependent mouse tests, which have separately recorded runs. Do not repeat full testing solely for documentation or packaging changes.

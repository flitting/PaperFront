# Architecture and development / 工程接口与开发

Paper Front uses **Godot 4.6.2 stable**, GDScript and a project-authored C++ GDExtension. The desktop renderer is Forward+ / Vulkan. Open [project.godot](../project.godot) in the standard Godot editor, or launch current source with `./run.sh`.

本项目继续采用 Godot、GDScript 和项目自写 C++ 扩展。规则模拟与画面呈现分离；本文描述当前接口，具体函数签名以源码为准。

## Ownership of state / 状态归属

| Layer | Entry points | Responsibility |
|---|---|---|
| Rule definitions | [data/rules.json](../data/rules.json), [rules_loader.gd](../scripts/rules_loader.gd) | Prices, factions, prerequisites, weapons and validation |
| Authoritative simulation | [simulation.gd](../scripts/simulation.gd) and its modules | Economy, construction, movement, targeting, damage, visibility, victory and saved state |
| AI | [ai_controller.gd](../scripts/ai_controller.gd), [ai_faction_adapter.gd](../scripts/ai_faction_adapter.gd) | Decisions sent through ordinary simulation commands |
| Input and camera | [main.gd](../scripts/main.gd) | UI sessions, selection, command targeting, camera and save/load orchestration |
| Presentation | [paper_world.gd](../scripts/paper_world.gd), [paper_hud.gd](../scripts/paper_hud.gd), [minimap.gd](../scripts/minimap.gd) | Read simulation state to draw models, cards, overlays, effects and map |
| Native kernels | [native/src](../native/src), [native build guide](../native/README.md) | Hot simulation, geometry and rendering submission paths with script comparison controls |
| Headless | [headless_main.gd](../scripts/headless_main.gd), [headless_match.gd](../scripts/headless_match.gd) | Simulation-only matches and statistics, without the battlefield renderer |

Simulation positions use `Vector2(x, z)`; terrain height comes from `MapData.height_at(map, position)`. Entity IDs and faction IDs are stable references, not display names. Public display names can be translated or renamed without replacing saved identifiers.

`WarSimulation` holds the map, entities, resources, commands, orders, projectiles, statistics and match result. Its main command surface includes setup, `step`, build/place/cancel, produce, `issue`, save and load. Modules such as `production_lifecycle`, `field_construction`, `armor_combat`, `infantry_squads`, `rail_network` and `team_vision` implement focused parts of the same authoritative state.

规则状态由 `WarSimulation` 持有。UI 与画面不得另建一套经济或战斗规则；AI 通过普通付费建造、生产和命令接口行动。坐标为地面 x/z，模型与 UI 只读取实际模拟结果。

## Presentation and data / 呈现与数据

Buildings and vehicles use authored procedural model geometry; infantry use cut-paper assets; the Creator Hand uses a separately attributed skinned mesh. `PaperWorld` reads real positions, animation states, projectiles and damage events. Near/far/extreme model tiers and scenery batching affect rendering rather than entity counts, simulation time or collision rules.

The Wiki is also a reader. Its catalog, statistics, previews and audio browser must not mutate the match rules. English translations are in [data/localization](../data/localization); [localization.gd](../scripts/localization.gd) translates presentation while retaining Chinese source content in rules and saves. Interface and voice language are separate preferences.

Production cards calculate whole-squad purchases through [infantry_squads.gd](../scripts/infantry_squads.gd). Each soldier remains an independent entity; production, refunds, save/load, transport and casualty statistics must preserve that distinction.

## Saving and reports / 存档与统计

[sim_save_validator.gd](../scripts/sim_save_validator.gd) validates save structure and versions before a loaded state replaces the current one. Saves retain actual maps, rule snapshots, stable entities, orders and accumulated statistics. Derived navigation/rendering caches can be rebuilt. Old snapshots must not silently inherit incompatible new rules.

[match_statistics.gd](../scripts/match_statistics.gd) and [match_statistics_exporter.gd](../scripts/match_statistics_exporter.gd) own time-series/event capture and JSON/CSV export. A report is a numerical history, not a playable replay. See [headless and statistics](balance_preparation.md).

## Change workflow / 修改流程

1. Change the owning rule/module, then update affected UI descriptions and translations.
2. Use focused regression tests for changed simulation or serialization behavior. Run `PAPER_FRONT_GODOT=godot ./tools/test.sh` for the complete project runner when validating a release.
3. For visual changes, render the actual project, inspect screenshots and check affected selection/collision/readability behavior. Use the [visual reference guide](visual_target.md).
4. Regenerate the [faction reference](faction_catalog.md) with `python3 tools/document_faction_catalog.py` after rule/catalog edits.
5. Rebuild native kernels after C++ changes and compare affected native/script behavior. Run GPU performance measurements one at a time without concurrent compilation.
6. Package current sources with `python3 tools/build_release.py --version 0.8.0 --output artifacts/release_20261011`; keep actual verification scope in the release record.

代码、测试与运行包应来自同一份规则和源码。不要把旧报告的通过数量、源码测试或交叉编译结果写成当前发行包的实机验证。

## Export profiles / 导出配置

| Profile | Purpose |
|---|---|
| `Linux` | Development export with the `development` feature |
| `Linux Shipping` | Player Linux build without the development feature |
| `Windows Portable` | Player Windows build with portable data handling |
| `Linux Headless` | Simulation-only export with `headless_sim` |

Export templates must match Godot 4.6.2. Player packages exclude tests, development tools, documentation references and historical retired audio. Headless dependencies are listed explicitly and checked by [headless_export_manifest.py](../tools/headless_export_manifest.py).

The Godot engine is not modified. Engine/dependency and asset notices remain separate from the project source-code licensing boundary described in [the README](../README.md).

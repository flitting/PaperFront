# Documentation / 文档索引

Start with [the bilingual game README](../README.md) for downloads, controls, factions and getting started. Current release information is in [release notes](release_notes.md) and the [validation record](release_validation.md).

玩家下载、操作、阵营及入门请先阅读仓库首页；当前构建与验证范围以发布说明为准。

## Current guides / 当前指南

| Guide | Purpose / 用途 |
|---|---|
| [Game mechanics](design.md) | Construction, economy, power, squads, combat and persistence / 当前玩法 |
| [Architecture](architecture.md) | State ownership, simulation/rendering boundary and change workflow / 工程接口 |
| [Faction reference](faction_catalog.md) | Generated bilingual unit, building and weapon data / 自动生成的现行数值 |
| [Windows portable](windows_portable.md) | Launcher, data, caches, build requirements / 便携版使用与构建 |
| [Native module](../native/README.md) | Linux/Windows C++ builds and script comparison switches / 原生模块 |
| [Headless and statistics](balance_preparation.md) | Symmetric map, JSON/CSV exports and command scripts / 无渲染运行与报告 |
| [AI balance experiments](ai_balance_experiments.md) | Batch match conditions, reliability and analysis / 数值实验 |
| [Independent AI modules](independent_ai_duel.md) | Strategy/recorder interface and controlled league protocol / 独立策略接口 |
| [Visual references](visual_target.md) | Art direction and reproducible screenshot checks / 美术参考与采集 |

## Attribution and design references / 来源与设定

| Reference | Scope / 范围 |
|---|---|
| [Asset licenses](../assets/LICENSE.md) | Asset and third-party license boundaries / 素材与依赖许可 |
| [Player-package credits](demo_credits.md) | English-first credits copied into current packages / 玩家包制作名单 |
| [Current Chinese audio production](revision_v8_audio.md) | Provider, generation and audio provenance / 中文音频来源 |
| [English speech](../assets/audio/english/README.md) | Local synthesis, stock voice attribution and regeneration / 英语语音 |
| [Map concept records](map_design_v6/requirements.md) | Briefs, prompts, concept generation and source checksums / 地图概念来源 |
| [Worldbuilding](派系设定/paper_front_world_setting_four_factions.md) | Dated story/art background, including future ideas / 历史设定与长期构想 |

User-provided style references, hand poses and worldbuilding images remain as documentation sources. They are excluded from player packages and are not declared project-authored CC0 artwork.

## Selected historical evidence / 保留的历史证据

- [AI comparison, 2026-10-07](ai_balance_results_20261007.md)
- [AI reliability, 2026-10-08](ai_reliability_results_20261008.md)
- [Independent league, 2026-10-08](independent_ai_duel_results_20261008.md)
- [v5 receipt](expansion_v5_validation.md) and [v6 receipt](revision_v6_validation.md): retained for the legacy expansion packager and asset traceability.

These reports describe their own dated builds. Their generated `artifacts/` evidence is local output, not part of a clean source checkout, and their pass counts do not certify the current release. Redundant intermediate plans, handoff notes and superseded revision reports have been removed from the active docs; their prior tracked versions remain in Git history.

这些报告仅证明对应日期和实验条件下的结果。已清理重复的中间计划、交接和旧版流水账；原先已提交内容仍可由 Git 历史追溯。

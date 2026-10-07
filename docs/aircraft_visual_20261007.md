# Aircraft and Creator hand visual revision — 2026-10-07

This revision keeps simulation flight height, damage, projectile timing and navigation unchanged. Aircraft anticipate terrain through a private render altitude (`model.visual_air_y`). Their authored model, muzzle, visual projectiles, air-target impact effects and continuous exhaust ribbons use that same altitude. The main picker reads this field separately.

Airborne deaths retain the real painted aircraft, continue along its measured horizontal velocity, pitch downward on a parabolic path and leave dark smoke. Fragments and a small contact effect appear only when the actual mesh bounds reach terrain or water. The contact never writes a simulation event or runs damage. Land contacts leave the existing flat scorch; water contacts leave no land scorch. Previous infantry fall/shatter, quiet building sale, Creator crush, vehicle/building clustered destruction, tank tracks and cloud shadows remain intact.

The Creator hand now has a team-color wrist cuff, dorsal chevron and tinted fingernails. Skin outside those regions retains its natural shader. Each instance owns its paint uniforms and nail material; the original continuous imported mesh, shared Skin, private sixteen-bone skeleton, animation and shadow remain in use at every model LOD.

## Budgets

| Feature | Normal/balanced | Performance | Lifetime/LOD |
| --- | ---: | ---: | --- |
| Real falling aircraft | 12 | 6 | Up to 6 seconds; authored near/far/ultra meshes |
| Crash smoke data | 192 | 96 | 2.8 seconds; 80/36/8-triangle sphere meshes |
| Continuous exhaust segments | 384 | 128 | 2.4 seconds; 8/4/2 triangles per segment |

Overflow retires the oldest crash quietly; it cannot manufacture a contact blast while the aircraft remains airborne. Offscreen falls still advance and expire. Quality changes retain up to six active falls. Fog and camera visibility suppress submissions; smoke uses three shared MultiMesh batches with a soft-rim shader rather than scene nodes per puff.

Terrain anticipation derives the needed distance from the cached full-map height span and the aircraft speed, up to a bounded 128 meters, including lateral hull clearance. Its envelope slope remains below the available climb rate. Normal ascent is capped at 5.2 meters/second and descent at 2.3; a current-terrain safety floor prevents clipping. A teleport or abrupt artificial terrain replacement can engage that floor immediately. Native culling retains a conservative map-height margin because the native entity cache still uses logical altitude.

## Validation

Logs are under `artifacts/aircraft_visual_20261007/`.

| Test | Checks/result |
| --- | --- |
| Aircraft visual motion | 420 passed: early ascent, continuous cliff crossing, sloped ribbons, safe clearance, no simulation mutation, real-model fall, contact-only debris, water, three LODs, quality/budget/offscreen cleanup, visual weapon offsets |
| Steep terrain overflight | 17 passed: real generated forest320 (18m full height span) and 14.8/16/20m vertical cliffs at 8/12m/s; every fixture has maximum frame altitude change 0.173333m at 30fps and at least 4.77m clearance |
| Creator hand owner colors | 19 passed: original mesh/Skin, private material uniforms, eight palette colors, surface regions and preserved animation |
| Creator hand world | 15 passed, clean renderer teardown |
| Destruction / clustered destruction | 74 / 38 passed |
| Infantry/sale/trails/cloud lifecycle | 88 passed |
| Effect LOD | 80 passed |
| Creator crush | 26 passed |
| Native world lifecycle | 7,681 passed |
| Model LOD / model poses | 90 / 2,264 passed |
| Performance effects | Passed; pooled effects expired, no failures |

Real GPU evidence: all fourteen final 1600×900 PNGs were rendered and inspected on Intel Arc MTL using Forward+. `tools/capture_aircraft_visual_20261007.gd` writes `artifacts/aircraft_visual_20261007/visual/capture_report.json`; capture log and renderer teardown are clean.

| Evidence | Observation |
| --- | --- |
| `terrain_flight_70/106/144/215.png` | A 12m/s aircraft climbs before a 20m plateau, retains continuous inclined twin ribbons, reaches 25m absolute altitude above the shelf, then descends gradually |
| `aircraft_crash_first_frame/t0_3/t0_65.png` | The original plane persists, advances and pitches down while its dark smoke grows; no pre-contact fireball or debris |
| `aircraft_crash_lod_near/far/ultra.png` | Aircraft geometry is 2,312/985/527 triangles; four smoke puffs submit 320/144/32 triangles at the same animation time |
| `aircraft_crash_ground_wreck.png` | Contact ends the fall, yields ten painted fragments and one land scorch, and retains the dark descending smoke trail |
| `creator_hand_owners_near/far/ultra.png` | Gold and cyan wrist, dorsal and nail accents remain distinct while natural skin, continuous geometry and hand shadows remain visible |

The steep-cliff regression was measured before repair: the old fixed 24m lookahead allowed a 6.63m single-frame jump at a 20m cliff and 12m/s. `aircraft_steep_terrain_before.log` preserves that failing reproduction; `aircraft_steep_terrain_tests.log` is the passing final result.

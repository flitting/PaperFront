#!/usr/bin/env sh
set -eu
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GODOT_BIN=${PAPER_FRONT_GODOT:-godot}
export XDG_DATA_HOME=${PAPER_FRONT_TEST_DATA:-/tmp/paper-front-tests}
export XDG_CONFIG_HOME=${PAPER_FRONT_TEST_CONFIG:-/tmp/paper-front-test-config}
# Godot may return success after a GDScript runtime error. Treat the log as
# part of the result so a later assertion cannot hide an earlier engine error.
run_godot() {
    paper_test_log=$(mktemp /tmp/paper-front-test-log.XXXXXX)
    paper_test_status=0
    "$GODOT_BIN" "$@" >"$paper_test_log" 2>&1 || paper_test_status=$?
    cat "$paper_test_log"
    if grep -Eq 'SCRIPT ERROR:|^ERROR:|ObjectDB instances leaked|resources still in use at exit|RID(s)? of type .*leaked' "$paper_test_log"; then
        paper_test_status=1
    fi
    rm -f "$paper_test_log"
    return "$paper_test_status"
}
run_godot --headless --path "$PROJECT_DIR" --editor --import --quit
for TEST_SCRIPT in symmetric_map_tests symmetric_map_navigation_tests match_telemetry_tests settlement_history_ui_tests headless_match_tests; do
    run_godot --headless --path "$PROJECT_DIR" --script "res://tests/$TEST_SCRIPT.gd"
done
for TEST_SCRIPT in developer_tools_tests developer_tools_input_tests; do
    run_godot --headless --path "$PROJECT_DIR" --script "res://tests/$TEST_SCRIPT.gd"
done
for TEST_SCRIPT in map_rules_tests battlefield_profile_tests battlefield_environment_tests stage3_sim_tests stage3_island_ai_tests stage3_shipyard_queue_tests naval_stage3_tests naval_native_combat_tests naval_integration_tests demo_transport_regression_tests naval_world_input_tests skirmish_setup_tests stage3_hud_tests stage4_core_tests stage4_campaign_integration_tests creator_hand_tests creator_hand_world_tests creator_crush_effects_tests creator_crush_metadata_v6_tests water_shipyard_v6_tests naval_legacy_ai_v6_tests naval_bridge_routes_v6_tests map_design_v6_tests base_vision_tests map_save_landmarks_v6_tests campaign_map_tests campaign_flow_tests campaign_ui_tests campaign_real_commands_tests mountain_map_tests mountain640_map_tests game_rules_tests victory_buildings_tests simulation_cache_tests native_nearest_tests native_lifetime_tests native_terrain_mask_tests native_unit_tick_tests simulation_render_overlap_tests native_geometry_tests support_repair_equivalence_tests multiteam_simulation_tests gameplay_performance_fixture_tests mining_force_rules_tests engineer_rules_tests outpost_construction_tests construction_force_input_tests scenery_interaction_tests scenery_performance_tests terrain_disk_cache_tests pine_shadow_tests renderer_cache_tests native_frustum_tests pose_mesh_tests model_pool_quality_tests native_volume_tests native_world_sync_tests native_world_cache_tests native_render_batch_tests performance_fx_tests eight_owner_render_tests unit_lod_provenance_tests model_lod_tests scenery_lod_tests camera_height_tests camera_pitch_tests camera_smoothing_tests minimap_camera_tests bridge_seam_tests scout_transport_tests unified_transport_tests contextual_transport_commands_tests unified_transport_input_tests construction_channels_tests tech_visibility_tests wall_connection_tests selection_path_tests engineer_transport_input_tests transport_world_tests ui_tests right_dock_tests menu_loading_tests loading_fps_tests wiki_catalog_tests wiki_preview_tests wiki_ui_tests skirmish_tests navigation_tests free_navigation_tests air_navigation_tests any_angle_worker_tests path_budget_tests path_geometry_invalidation_tests path_throughput_tests debug_spawn_navigation_tests gameplay_polish_tests refinement_tests landscape_tests audio_tests faction_catalog_tests balance_tests economy_parity_tests air_superiority_tests faction_trait_tests local_power_tests rivet_mechanics_tests rivet_save_tests faction_traits_ui_tests faction_revision_tests faction_support_input_tests airforce_tests faction_visual_tests faction_ui_audio_tests building_mass_tests; do
    run_godot --headless --path "$PROJECT_DIR" --script "res://tests/$TEST_SCRIPT.gd"
done
for TEST_SCRIPT in combat_feedback_events_tests battlefield_destruction_tests battlefield_destruction_v9_tests battlefield_lifecycle_v9_tests battlefield_effect_lod_tests combat_audio_v8_tests voice_profile_routing_tests unit_identity_continuity_tests adaptive_music_tests adaptive_music_game_tests audio_browser_catalog_tests audio_browser_tests audio_browser_settings_tests audio_browser_transport_tests audio_browser_v10_input_tests audio_animation_preview_tests audio_attention_v10_tests feedback_v10_core_tests large_map_zoom_v10_tests scoreboard_integration_v10_tests new_battle_scoreboard_tests scoreboard_page_v11_tests camera_cliff_v11_tests main_feedback_v11_tests navigation_priority_pursuit_tests; do
    run_godot --headless --path "$PROJECT_DIR" --script "res://tests/$TEST_SCRIPT.gd"
done
for TEST_SCRIPT in construction_range_v7_tests world_visual_v7_tests fog_native_v7_tests demo_audio_tests demo_audio_mix_tests audio_restore_tests settings_menu_tests demo_menu_flow_tests demo_campaign_hints_tests demo_campaign_live_tests demo_navigation_geometry_tests demo_navigation_control_tests demo_hand_owner_tests; do
    run_godot --headless --path "$PROJECT_DIR" --script "res://tests/$TEST_SCRIPT.gd"
done
run_godot --headless --path "$PROJECT_DIR" --script res://tests/demo_shutdown_tests.gd -- --shutdown-mode=start
run_godot --headless --path "$PROJECT_DIR" --script res://tests/demo_shutdown_tests.gd -- --shutdown-mode=load
run_godot --headless --path "$PROJECT_DIR" --script res://tests/demo_transport_regression_tests.gd -- --native
run_godot --headless --path "$PROJECT_DIR" --script res://tests/native_unit_tick_tests.gd -- --threaded-tick-equivalence
run_godot --headless --path "$PROJECT_DIR" --script res://tests/campaign_real_commands_tests.gd -- --campaign-ai
run_godot --headless --path "$PROJECT_DIR" --script res://tests/depth_of_field_tests.gd
run_godot --headless --path "$PROJECT_DIR" --script res://tests/model_detail_tests.gd
run_godot --headless --path "$PROJECT_DIR" --script res://tools/check_art.gd

run_godot --headless --path "$PROJECT_DIR" --script res://tools/check_volume_models.gd
run_godot --headless --path "$PROJECT_DIR" --script res://tools/check_faction_buildings.gd
run_godot --headless --path "$PROJECT_DIR" --script res://tools/check_building_roof_selection.gd

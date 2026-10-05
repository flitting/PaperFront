#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <algorithm>
#include <cmath>
#include <vector>
#include <chrono>
#include <godot_cpp/variant/plane.hpp>
using namespace godot;

#include "spatial_index.hpp"
#include "terrain_mask.hpp"
#include "sight_mask.hpp"
#include <godot_cpp/classes/node3d.hpp>
#include "render_batch.hpp"
#include "volume_pose.hpp"
#include "repair_support.hpp"
#include "unit_tick.hpp"
#include "geometry_queries.hpp"
#include "ground_movement.hpp"
#include "world_model_cache.hpp"
#include "world_sync.hpp"

// Exact numeric kernels only. The GDScript simulation owns all gameplay state,
// clocks, command order, damage and lifecycle, with its reference fallback.
class PaperFrontKernels : public RefCounted {
    GDCLASS(PaperFrontKernels, RefCounted)
    PoseKeys pose_keys;
    TargetKeys target_keys;
    UnitKeys unit_keys;
    GeometryQueries geometry;
    SightMaskSampler sight_mask;
    MovementKeys movement_keys;
    WorldKeys world_keys;
    WorldModelCache world_models;
    BatchKeys batch_keys;
    RenderBatchRegistry render_batches;
    bool world_profiling=false;
    std::vector<Plane> view_planes;
    std::vector<double> view_sides;
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("clear_world_models"), &PaperFrontKernels::clear_world_models);
        ClassDB::bind_method(D_METHOD("register_render_batch","batch"), &PaperFrontKernels::register_batch);
        ClassDB::bind_method(D_METHOD("clear_render_batches"), &PaperFrontKernels::clear_batches);
        ClassDB::bind_method(D_METHOD("begin_render_batches","batches"), &PaperFrontKernels::begin_batches);
        ClassDB::bind_method(D_METHOD("flush_render_batches","batches","bulk"), &PaperFrontKernels::flush_batches);
        ClassDB::bind_method(D_METHOD("move_ground", "simulation", "entity", "goal", "delta"), &PaperFrontKernels::move_ground);
        ClassDB::bind_method(D_METHOD("movement_clear", "simulation", "entity", "start", "next", "request_yield"), &PaperFrontKernels::movement_clear);
        ClassDB::bind_method(D_METHOD("build_flat_terrain_mask", "map"), &PaperFrontKernels::build_flat_terrain_mask);
        ClassDB::bind_method(D_METHOD("refresh_sight_mask", "map", "observers", "changed_buckets", "pixels"), &PaperFrontKernels::refresh_sight_mask);
        ClassDB::bind_method(D_METHOD("verify_container_lifetimes"), &PaperFrontKernels::verify_container_lifetimes);
        ClassDB::bind_method(D_METHOD("set_world_profiling", "enabled"), &PaperFrontKernels::set_world_profiling);
        ClassDB::bind_method(D_METHOD("sync_world_entities", "world", "entities", "models", "selected", "map", "policy", "elapsed", "yaw", "capacity", "construction_time"), &PaperFrontKernels::sync_world_entities);
        ClassDB::bind_method(D_METHOD("configure_geometry", "data"), &PaperFrontKernels::configure_geometry);
        ClassDB::bind_method(D_METHOD("begin_geometry_measurement", "enabled"), &PaperFrontKernels::begin_geometry_measurement);
        ClassDB::bind_method(D_METHOD("geometry_measurement"), &PaperFrontKernels::geometry_measurement);
        ClassDB::bind_method(D_METHOD("standing", "position", "radius", "ignore", "dynamic"), &PaperFrontKernels::standing);
        ClassDB::bind_method(D_METHOD("near_stand", "position", "radius", "ignore", "maximum", "dynamic"), &PaperFrontKernels::near_stand);
        ClassDB::bind_method(D_METHOD("segment_static", "start", "end", "radius", "ignore"), &PaperFrontKernels::segment_static);
        ClassDB::bind_method(D_METHOD("building_clear", "position", "radius", "ignore"), &PaperFrontKernels::building_clear);
        ClassDB::bind_method(D_METHOD("step_entities", "simulation", "entities", "specs", "weapons", "air_specs", "naval_specs", "masks", "multipliers", "delta", "fire_angle"), &PaperFrontKernels::step_entities);
        ClassDB::bind_method(D_METHOD("set_frustum", "planes", "sides"), &PaperFrontKernels::set_frustum);
        ClassDB::bind_method(D_METHOD("point_in_view", "position", "radius"), &PaperFrontKernels::point_in_view);
        ClassDB::bind_method(D_METHOD("repair_support", "entities", "stations", "field", "specs", "money", "air_specs", "delta", "cost"), &PaperFrontKernels::repair_support);
        ClassDB::bind_method(D_METHOD("can_target", "source", "target", "entities", "mask", "air_specs", "naval_specs", "force"), &PaperFrontKernels::can_target);
        ClassDB::bind_method(D_METHOD("update_volume", "model", "entity", "selected", "camera_yaw", "elapsed", "capacity", "construction_time"), &PaperFrontKernels::update_volume);
        ClassDB::bind_method(D_METHOD("rebuild_spatial", "entities", "faction_count", "air_specs", "naval_specs"), &PaperFrontKernels::rebuild_spatial);
        ClassDB::bind_method(D_METHOD("nearest_enemy", "source", "range", "team", "mask", "buckets", "ids", "positions", "teams", "domains", "visibility"), &PaperFrontKernels::nearest_enemy);
    }
public:
    void clear_world_models() { world_models.clear(); }
    void register_batch(const Dictionary &batch) { render_batches.add(batch); }
    void clear_batches() { render_batches.clear(); }
    void begin_batches(const Dictionary &) { render_batches.begin(batch_keys); }
    Vector3i flush_batches(const Dictionary &,bool bulk) { return render_batches.flush(batch_keys,bulk); }
    bool move_ground(Object *sim, Dictionary entity, Vector2 goal, double delta) { return GroundMovement{sim, geometry, movement_keys}.move(entity, goal, delta); }
    bool movement_clear(Object *sim, Dictionary entity, Vector2 start, Vector2 next, bool request_yield) { return GroundMovement{sim, geometry, movement_keys}.clear(entity, start, next, request_yield); }
    PackedByteArray build_flat_terrain_mask(const Dictionary &map) const { return build_flat_terrain_mask_native(map); }
    Dictionary refresh_sight_mask(const Dictionary &map, const Dictionary &observers, const Dictionary &changed_buckets, const PackedByteArray &pixels) { return sight_mask.refresh(map, observers, changed_buckets, pixels); }
    Dictionary verify_container_lifetimes() const {
        Ref<RefCounted> object; object.instantiate();
        int64_t after_move=0, after_self=0;
        {
            Dictionary value; value["object"]=object;
            Dictionary replacement; replacement["number"]=7;
            value=Dictionary(replacement);
            after_move=object->get_reference_count();
            value["object"]=object;
            value=value;
            value=std::move(value);
            after_self=object->get_reference_count();
        }
        Dictionary result; result["after_move"]=after_move; result["after_self"]=after_self; result["after_scope"]=object->get_reference_count();
        return result;
    }
    void set_world_profiling(bool enabled) { world_profiling=enabled; }
    Dictionary sync_world_entities(Object *world, const Dictionary &entities, Dictionary models, const Dictionary &selected, const Dictionary &map, const String &policy, double elapsed, double yaw, double capacity, double construction_time) { return sync_world_native(world, entities, models, selected, map, policy, elapsed, yaw, capacity, construction_time, view_planes, view_sides, pose_keys, world_keys, world_models, world_profiling); }
    void configure_geometry(const Dictionary &data) { geometry.configure(data); }
    void begin_geometry_measurement(bool enabled) { geometry.begin_measurement(enabled); }
    Dictionary geometry_measurement() const { return geometry.measurement(); }
    bool standing(Vector2 position, double radius, int64_t ignore, bool dynamic) { return geometry.standing(position, radius, ignore, dynamic); }
    Vector2 near_stand(Vector2 position, double radius, int64_t ignore, double maximum, bool dynamic) { return geometry.near_stand(position, radius, ignore, maximum, dynamic); }
    bool segment_static(Vector2 start, Vector2 end, double radius, int64_t ignore) { return geometry.segment_static(start, end, radius, ignore); }
    bool building_clear(Vector2 position, double radius, int64_t ignore) { return geometry.building_clear(position, radius, ignore); }
    void step_entities(Object *sim, const Dictionary &entities, const Dictionary &specs, const Dictionary &weapons, const Dictionary &air_specs, const Dictionary &naval_specs, const Dictionary &masks, const Array &multipliers, double delta, double fire_angle) { step_entities_native(sim, entities, specs, weapons, air_specs, naval_specs, masks, multipliers, delta, fire_angle, unit_keys, target_keys); }
    void set_frustum(const Array &planes, const Array &sides) {
        const int64_t count = std::min(planes.size(), sides.size());
        view_planes.resize(count); view_sides.resize(count);
        for (int64_t i = 0; i < count; ++i) { view_planes[i] = Plane(planes[i]); view_sides[i] = double(sides[i]); }
    }
    bool point_in_view(Vector3 position, double radius) const {
        for (size_t i = 0; i < view_planes.size(); ++i) {
            if (double(view_planes[i].distance_to(position)) * view_sides[i] < -radius) return false;
        }
        return true;
    }
    void repair_support(const Dictionary &entities, const Dictionary &stations, const Dictionary &field, const Dictionary &specs, Array money, const Dictionary &air_specs, double delta, double cost) { repair_support_native(entities, stations, field, specs, money, air_specs, delta, cost); }
    bool can_target(const Dictionary &source, int64_t target, const Dictionary &entities, int64_t mask, const Dictionary &air_specs, const Dictionary &naval_specs, bool force) const { return can_target_native(source, target, entities, mask, air_specs, naval_specs, force, target_keys); }
    int64_t update_volume(Dictionary model, const Dictionary &entity, bool selected, double camera_yaw, double elapsed, double capacity, double construction_time) const { return update_volume_native(model, entity, selected, camera_yaw, elapsed, capacity, construction_time, pose_keys); }
    Dictionary rebuild_spatial(const Dictionary &entities, int64_t faction_count, const Dictionary &air_specs, const Dictionary &naval_specs) const { return rebuild_spatial_native(entities, faction_count, air_specs, naval_specs); }
    int64_t nearest_enemy(Vector2 source, double range, int64_t team, int64_t mask,
        const Dictionary &buckets, const PackedInt64Array &ids, const PackedVector2Array &positions,
        const PackedInt32Array &teams, const PackedByteArray &domains, const PackedByteArray &visibility) const {
        if (!std::isfinite(range) || range < 0 || !source.is_finite()) return -1;
        // Vector2 operations match the engine's single-precision vector math;
        // GDScript's scalar distances and bucket bounds remain doubles.
        const Vector2 first_pos = source - Vector2(1, 1) * range;
        const Vector2 last_pos = source + Vector2(1, 1) * range;
        int first_x = std::floor(first_pos.x / 8.0), first_z = std::floor(first_pos.y / 8.0);
        int last_x = std::floor(last_pos.x / 8.0), last_z = std::floor(last_pos.y / 8.0);
        int cx = std::floor(source.x / 8.0), cz = std::floor(source.y / 8.0);
        int rings = std::max({cx - first_x, last_x - cx, cz - first_z, last_z - cz});
        int64_t nearest = -1, winner_bucket = -1, winner_index = -1;
        double distance = range * range;
        int width = last_x - first_x + 1;
        const int64_t size = std::min({ids.size(), positions.size(), teams.size(), domains.size(), visibility.size()});
        for (int ring = 0; ring <= rings; ++ring) {
            for (int z = std::max(first_z, cz - ring); z <= std::min(last_z, cz + ring); ++z) {
                for (int x = std::max(first_x, cx - ring); x <= std::min(last_x, cx + ring); ++x) {
                    if (std::max(std::abs(x - cx), std::abs(z - cz)) != ring) continue;
                    double dx = std::max({double(x * 8) - source.x, double(source.x) - (x + 1) * 8, 0.0});
                    double dz = std::max({double(z * 8) - source.y, double(source.y) - (z + 1) * 8, 0.0});
                    if (dx * dx + dz * dz > distance + std::max(.00001, distance * .0000003)) continue;
                    Variant bucket = buckets.get(Vector2i(x, z), Variant());
                    if (bucket.get_type() != Variant::ARRAY) continue;
                    Array slots = bucket;
                    int rank = (z - first_z) * width + x - first_x;
                    for (int64_t index = 0; index < slots.size(); ++index) {
                        int64_t slot = slots[index];
                        if (slot < 0 || slot >= size) continue;
                        if (teams[slot] == team || !(domains[slot] & mask) || !(visibility[slot] & (1 << team))) continue;
                        double candidate = source.distance_squared_to(positions[slot]);
                        if (candidate > distance) continue;
                        if (candidate == distance && (rank < winner_bucket || (rank == winner_bucket && index < winner_index))) continue;
                        distance = candidate;
                        nearest = ids[slot];
                        winner_bucket = rank;
                        winner_index = index;
                    }
                }
            }
        }
        return nearest;
    }
};
void initialize_kernels(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) {
        ClassDB::register_class<PaperFrontRenderBatch>();
        ClassDB::register_class<PaperFrontRenderRecord>();
        ClassDB::register_class<PaperFrontKernels>();
    }
}
void uninitialize_kernels(ModuleInitializationLevel) {}
extern "C" {
GDExtensionBool GDE_EXPORT paper_front_kernels_init(GDExtensionInterfaceGetProcAddress get_proc_address,
    GDExtensionClassLibraryPtr library, GDExtensionInitialization *initialization) {
    GDExtensionBinding::InitObject init(get_proc_address, library, initialization);
    init.register_initializer(initialize_kernels);
    init.register_terminator(uninitialize_kernels);
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
}

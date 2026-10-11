#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

// Performance-tier volume pose and batch submission; no authoritative writes.
// Cache the boxed dictionary key as well as its interned name. Passing a bare
// StringName would construct and release a temporary Variant at every lookup.
struct PoseKeys {
    const Variant native_render_record{StringName{"native_render_record"}};
    const Variant embarked{StringName{"embarked"}};
    const Variant transport_id{StringName{"transport_id"}};
    const Variant root{StringName{"root"}};
    const Variant pos{StringName{"pos"}};
    const Variant last_pos{StringName{"last_pos"}};
    const Variant terrain_height{StringName{"terrain_height"}};
    const Variant art_root{StringName{"art_root"}};
    const Variant hp_root{StringName{"hp_root"}};
    const Variant spec{StringName{"spec"}};
    const Variant volume{StringName{"volume"}};
    const Variant is_air{StringName{"is_air"}};
    const Variant flight_height{StringName{"flight_height"}};
    const Variant base_hp_height{StringName{"base_hp_height"}};
    const Variant shadow{StringName{"shadow"}};
    const Variant dimensions{StringName{"dimensions"}};
    const Variant kind{StringName{"kind"}};
    const Variant state{StringName{"state"}};
    const Variant alpha{StringName{"alpha"}};
    const Variant rotation_quarters{StringName{"rotation_quarters"}};
    const Variant last_alpha{StringName{"last_alpha"}};
    const Variant turret{StringName{"turret"}};
    const Variant turret_alpha{StringName{"turret_alpha"}};
    const Variant last_turret_angle{StringName{"last_turret_angle"}};
    const Variant attack_flash{StringName{"attack_flash"}};
    const Variant hit_flash{StringName{"hit_flash"}};
    const Variant construct_remaining{StringName{"construct_remaining"}};
    const Variant scale{StringName{"scale"}};
    const Variant last_visual_elapsed{StringName{"last_visual_elapsed"}};
    const Variant last_hp_yaw{StringName{"last_hp_yaw"}};
    const Variant hp{StringName{"hp"}};
    const Variant hp_fraction{StringName{"hp_fraction"}};
    const Variant hp_width{StringName{"hp_width"}};
    const Variant hp_fill{StringName{"hp_fill"}};
    const Variant hp_fill_back{StringName{"hp_fill_back"}};
    const Variant render_parts{StringName{"render_parts"}};
    const Variant node{StringName{"node"}};
    const Variant performance_batch{StringName{"performance_batch"}};
    const Variant cargo{StringName{"cargo"}};
    const Variant cargo_count{StringName{"cargo_count"}};
    const Variant cargo_batches{StringName{"cargo_batches"}};
    const Variant shadow_batch{StringName{"shadow_batch"}};
    const Variant ring{StringName{"ring"}};
    const Variant ring_batch{StringName{"ring_batch"}};
    const Variant hp_bars{StringName{"hp_bars"}};
    const Variant hp_batches{StringName{"hp_batches"}};
    const Variant transforms{StringName{"transforms"}};
    const Variant body{StringName{"body"}};
    const Variant art{StringName{"art"}};
};
static Node3D *pose_node(const Dictionary &d, const Variant &key) {
    Object *object = d[key];
    return Object::cast_to<Node3D>(object);
}
// Numeric renderer state, valid only while the native bulk path owns updates.
// Public model fields are still updated for picking, tools and script fallback.
struct PoseStateCache {
    Vector2 position;
    double alpha=0, turret_angle=0, hp_yaw=0, flight=0, hp_fraction=0;
    String state;
    bool mirror=false;
    void load(const Dictionary &model,const PoseKeys &k) {
        position=model[k.last_pos]; alpha=model[k.last_alpha]; turret_angle=model[k.last_turret_angle];
        hp_yaw=model[k.last_hp_yaw]; flight=model[k.flight_height]; hp_fraction=model[k.hp_fraction];
        state=model[k.state]; mirror=model.get("mirror",false);
    }
};
// Stable renderer references belong to each model, not to the simulation.
// This resource never owns its containing Dictionary, avoiding reference cycles.
class PaperFrontRenderRecord : public RefCounted {
    GDCLASS(PaperFrontRenderRecord, RefCounted)
protected:
    static void _bind_methods() {}
public:
    Node3D *root=nullptr, *art=nullptr, *hp=nullptr, *shadow=nullptr, *ring=nullptr, *fill=nullptr, *fill_back=nullptr, *turret=nullptr;
    Dictionary spec, volume, shadow_batch, ring_batch;
    Array hp_bars, hp_batches, cargo, cargo_batches, source_parts;
    struct Part { Node3D *node; Dictionary batch; PaperFrontRenderBatch *queue; };
    std::vector<Part> parts;
    PaperFrontRenderBatch *shadow_queue=nullptr, *ring_queue=nullptr;
    std::vector<PaperFrontRenderBatch *> hp_queues, cargo_queues;
    bool volumetric=false, is_air=false, harvester=false, unit=false;
    PoseStateCache pose;
    Vector2 dimensions;
    double cull_radius=0, base_hp_height=0, hp_width=0;
    void initialize(const Dictionary &model, const PoseKeys &k) {
        root=pose_node(model,k.root); art=pose_node(model,k.art_root); hp=pose_node(model,k.hp_root);
        shadow=pose_node(model,k.shadow); ring=pose_node(model,k.ring); fill=pose_node(model,k.hp_fill); fill_back=pose_node(model,k.hp_fill_back);
        spec=model[k.spec]; volume=model[k.volume];
        volumetric=model["volumetric"]; is_air=model[k.is_air]; unit=String(model[k.kind])=="unit"; harvester=String(spec[k.art])=="harvester";
        dimensions=model[k.dimensions]; cull_radius=model["cull_radius"]; base_hp_height=model[k.base_hp_height]; hp_width=model[k.hp_width];
        hp_bars=model[k.hp_bars]; hp_batches=model[k.hp_batches]; shadow_batch=model[k.shadow_batch]; ring_batch=model[k.ring_batch];
        shadow_queue=render_batch(shadow_batch); ring_queue=render_batch(ring_batch);
        for (int64_t i=0;i<hp_batches.size();++i) hp_queues.push_back(render_batch(hp_batches[i]));
        if (volumetric) {
            Object *object=volume[k.turret]; turret=Object::cast_to<Node3D>(object);
            cargo=volume[k.cargo]; cargo_batches=model[k.cargo_batches]; source_parts=model[k.render_parts];
            for (int64_t i=0;i<cargo_batches.size();++i) cargo_queues.push_back(render_batch(cargo_batches[i]));
        }
    }
    void prepare_parts(const PoseKeys &k) {
        if (!parts.empty()) return;
        for (int64_t i=0;i<source_parts.size();++i) { Dictionary part=source_parts[i]; Dictionary batch=part[k.performance_batch]; parts.push_back({pose_node(part,k.node),batch,render_batch(batch)}); }
    }
};
static PaperFrontRenderRecord *render_record(Dictionary model, const PoseKeys &k) {
    const Variant &key=k.native_render_record;
    Object *object=model.get(key, Variant());
    auto *record=Object::cast_to<PaperFrontRenderRecord>(object);
    if (!record) {
        Ref<PaperFrontRenderRecord> created; created.instantiate(); created->initialize(model,k);
        model[key]=created; record=created.ptr();
    }
    return record;
}
int64_t update_volume_native(Dictionary model, const Dictionary &e, bool selected, double yaw,
    double elapsed, double capacity, double construction_time, const PoseKeys &k, PaperFrontRenderRecord *record=nullptr, bool record_submissions=true) {
    bool embarked = int64_t(e.get(k.transport_id, -1)) > 0 || int64_t(e.get(StringName("garrison_id"), -1)) >= 0;
    model[k.embarked] = embarked;
    if (embarked) return 0;
    if (!record) record=render_record(model,k);
    if (record_submissions) record->pose.load(model,k);
    auto &pose=record->pose;
    Node3D *root=record->root, *art=record->art, *hp=record->hp;
    const Dictionary &spec=record->spec; Dictionary volume=record->volume;
    Vector2 pos=e[k.pos], dimensions=record->dimensions;
    if (pose.position != pos) {
        root->set_position(Vector3(pos.x, double(model[k.terrain_height]), pos.y));
        model[k.last_pos] = pos; pose.position=pos;
    }
    double flight = record->is_air ? double(e.get(k.flight_height, spec.get(k.flight_height, 0.0))) : 0.0;
    Node3D *shadow = record->shadow;
    if (record->is_air && pose.flight != flight) {
        Vector3 position = art->get_position(); position.y = flight; art->set_position(position);
        position = hp->get_position(); position.y = record->base_hp_height + flight; hp->set_position(position);
        double factor = std::clamp(1.0 - flight * .035, .52, 1.0);
        shadow->set_scale(Vector3(dimensions.x * .40 * factor, 1, dimensions.x * .19 * factor));
    }
    if (pose.flight!=flight) { model[k.flight_height] = flight; pose.flight=flight; }
    String state("idle");
    Node3D *turret = record->turret;
    if (record->unit) {
        String source_state = e[k.state];
        if (source_state == "idle" || source_state == "move" || source_state == "attack") state = source_state;
        if (double(e.get(k.attack_flash, 0.0)) > 0) state = "attack";
        if (double(e.get(k.hit_flash, 0.0)) > 0) state = "hit";
        double alpha = UtilityFunctions::wrapf(double(e[k.alpha]), -180., 180.);
        if (pose.alpha != alpha) {
            Vector3 rotation = root->get_rotation(); rotation.y = -UtilityFunctions::deg_to_rad(alpha); root->set_rotation(rotation);
            model[k.last_alpha] = alpha; pose.alpha=alpha;
            root->set_meta(k.alpha, alpha);
        }
        if (!root->has_meta("mirrored")) root->set_meta("mirrored", false);
        if (turret) {
            double angle = -UtilityFunctions::deg_to_rad(UtilityFunctions::wrapf(double(e.get(k.turret_alpha, alpha)) - alpha, -180., 180.));
            if (pose.turret_angle != angle) {
                Vector3 rotation = turret->get_rotation(); rotation.y = angle; turret->set_rotation(rotation);
                model[k.last_turret_angle] = angle; pose.turret_angle=angle;
            }
        }
    } else {
        Dictionary building_spec = model[k.spec];
        String role = building_spec.get("role", "");
        double building_angle = (role == "rail" || role == "rail_junction") ? 0.0 : double(int64_t(e.get(k.rotation_quarters, 0)) % 4) * 90.0;
        if (pose.alpha != building_angle) {
            Vector3 rotation = root->get_rotation(); rotation.y = -UtilityFunctions::deg_to_rad(building_angle); root->set_rotation(rotation);
            model[k.last_alpha] = building_angle; pose.alpha = building_angle;
        }
        if (turret) {
            double angle = -UtilityFunctions::deg_to_rad(double(e.get(k.turret_alpha, 0.0)) - building_angle);
            if (pose.turret_angle != angle) {
                Vector3 rotation = turret->get_rotation(); rotation.y = angle; turret->set_rotation(rotation);
                model[k.last_turret_angle] = angle; pose.turret_angle=angle;
            }
        }
        double remaining = e.get(k.construct_remaining, 0.0);
        double progress = 1.0 - std::clamp(remaining / std::max(construction_time, .001), 0.0, 1.0);
        Vector3 scale = art->get_scale();
        if (remaining > 0 || scale.y != 1.0) { scale.y = .08 + .92 * progress; art->set_scale(scale); }
    }
    if (record->harvester) {
        const Array &cargo = record->cargo;
        volume[k.cargo_count] = int64_t(std::ceil(std::clamp(double(e.get(k.cargo, 0.0)) / capacity, 0.0, 1.0) * cargo.size()));
    }
    model[k.last_visual_elapsed] = elapsed;
    double hp_yaw = yaw - root->get_rotation().y;
    if (pose.hp_yaw != hp_yaw) {
        Vector3 rotation = hp->get_rotation(); rotation.y = hp_yaw; hp->set_rotation(rotation);
        model[k.last_hp_yaw] = hp_yaw; pose.hp_yaw=hp_yaw;
    }
    if (pose.state!=state) { model[k.state] = state; pose.state=state; }
    double fraction = std::clamp(double(e[k.hp]) / std::max(double(spec[k.hp]), .001), 0.0, 1.0);
    double width = record->hp_width;
    if (fraction != pose.hp_fraction) {
        for (Node3D *bar : {record->fill, record->fill_back}) {
            Vector3 scale = bar->get_scale(); scale.x = width * fraction; bar->set_scale(scale);
            Vector3 position = bar->get_position(); position.x = (fraction - 1.) * width * .5; bar->set_position(position);
        }
        model[k.hp_fraction] = fraction; pose.hp_fraction=fraction;
    }
    int64_t submitted = 0;
    Variant cached_submissions;
    if (record_submissions) cached_submissions=model.get("cached_submissions",Array());
    auto append = [&](const Dictionary &batch, const Transform3D &transform, PaperFrontRenderBatch *queue) {
        if (queue && queue->enabled) queue->append_transform(transform);
        else { Array transforms = batch[k.transforms]; transforms.push_back(transform); }
        ++submitted;
        if (record_submissions) { Array item; item.resize(3); item[0]=batch; item[1]=transform; Array(cached_submissions).push_back(item); }
    };
    record->prepare_parts(k);
    for (const auto &part : record->parts) append(part.batch, part.node->get_global_transform(),part.queue);
    const Array &cargo=record->cargo, &cargo_batches=record->cargo_batches;
    int64_t cargo_count = volume.get(k.cargo_count, 0);
    for (int64_t i = 0; i < cargo_count; ++i) {
        Object *object = cargo[i];
        append(cargo_batches[i], Object::cast_to<Node3D>(object)->get_global_transform(),record->cargo_queues[i]);
    }
    Transform3D transform = root->get_global_transform();
    append(record->shadow_batch, transform * shadow->get_transform(),record->shadow_queue);
    // Selection circles are disabled; squad boundaries are drawn by the HUD.
    if (selected || double(e.get(k.hit_flash, 0.0)) > 0) {
        Transform3D hp_transform = transform * hp->get_transform();
        const Array &bars=record->hp_bars, &batches=record->hp_batches;
        for (int64_t i = 0; i < bars.size(); ++i) {
            Object *object = bars[i];
            append(batches[i], hp_transform * Object::cast_to<Node3D>(object)->get_transform(),record->hp_queues[i]);
        }
    }
    return submitted;
}

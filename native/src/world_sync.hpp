#include <chrono>
struct WorldKeys {
    const Variant team{StringName{"team"}}, scaffold{StringName{"scaffold"}}, construction{StringName{"construction"}}, volumetric{StringName{"volumetric"}},
        last_terrain_pos{StringName{"last_terrain_pos"}}, cull_radius{StringName{"cull_radius"}}, view_culled{StringName{"view_culled"}},
        visual_signature{StringName{"visual_signature"}}, cached_submissions{StringName{"cached_submissions"}}, paper_batch{StringName{"paper_batch"}},
        mirror{StringName{"mirror"}}, mirrored{StringName{"mirrored"}}, graphic{StringName{"graphic"}}, domain{StringName{"domain"}},
        visible_to{StringName{"visible_to"}}, fog_hidden{StringName{"fog_hidden"}}, direct_skinned{StringName{"direct_skinned"}};
    const StringName create_entity{"_create_entity"}, sync_entity{"_sync_entity"}, start_death{"_start_death"}, paper_state{"_set_paper_state"};
    const String building{"building"}, idle{"idle"}, move{"move"}, attack{"attack"}, hit{"hit"}, performance{"performance"}, ground{"ground"}, naval{"naval"};
};
static double render_height(const Array &terrain, const Array &heights, int64_t size, Vector2 p) {
    int64_t x = std::clamp<int64_t>(std::floor(p.x), 0, size - 1), z = std::clamp<int64_t>(std::floor(p.y), 0, size - 1);
    Array row = heights[z]; double height = row[x];
    Array types = terrain[z];
    if (int64_t(types[x]) == 2) {
        double fraction = p.y - (z + .5);
        int64_t next = z + (fraction >= 0 ? 1 : -1);
        if (next >= 0 && next < size) {
            Array other = heights[next]; double next_height = other[x];
            if (std::abs(next_height - height) <= .75) return UtilityFunctions::lerpf(height, next_height, std::abs(fraction));
        }
    }
    return height;
}
static int64_t update_paper_native(Object *world, Dictionary model, const Dictionary &e, bool selected, double elapsed,
    const PoseKeys &k, const WorldKeys &w, PaperFrontRenderRecord *record) {
    bool embarked = int64_t(e.get(k.transport_id, -1)) > 0 || int64_t(e.get(StringName("garrison_id"), -1)) >= 0;
    model[k.embarked] = embarked;
    if (embarked) return 0;
    auto &pose=record->pose;
    Node3D *root=record->root, *art=record->art;
    const Dictionary &spec=record->spec;
    Vector2 position = e[k.pos];
    if (pose.position != position) {
        root->set_position(Vector3(position.x, double(model[k.terrain_height]), position.y));
        model[k.last_pos] = position; pose.position=position;
    }
    const double flight=record->is_air ? double(e.get(k.flight_height, spec.get(k.flight_height, 0.0))) : 0.0;
    if (pose.flight!=flight) { model[k.flight_height]=flight; pose.flight=flight; }
    String state = e[k.state];
    if (state != w.idle && state != w.move && state != w.attack) state = w.idle;
    if (double(e.get(k.attack_flash, 0.0)) > 0) state = w.attack;
    if (double(e.get(k.hit_flash, 0.0)) > 0) state = w.hit;
    const String previous_state = pose.state;
    double alpha = UtilityFunctions::wrapf(double(e[k.alpha]), -180., 180.);
    if (pose.alpha != alpha) {
        Vector3 rotation = root->get_rotation(); rotation.y = -UtilityFunctions::deg_to_rad(alpha); root->set_rotation(rotation);
        model[k.last_alpha] = alpha; pose.alpha=alpha; root->set_meta(k.alpha, alpha);
    }
    bool mirrored = std::abs(alpha) > 80.0;
    if (pose.mirror != mirrored) {
        Vector3 rotation = art->get_rotation(); rotation.y = mirrored ? Math_PI : 0.0; art->set_rotation(rotation);
        Vector3 scale = art->get_scale(); scale.x = mirrored ? -1.0 : 1.0; art->set_scale(scale);
        model[w.mirror] = mirrored; pose.mirror=mirrored; root->set_meta(w.mirrored, mirrored);
    } else if (!root->has_meta(w.mirrored)) root->set_meta(w.mirrored, mirrored);
    if (state == w.move) {
        Vector3 rotation = art->get_rotation(); rotation.z = UtilityFunctions::sin(elapsed * 12.0 + double(e["id"])) * .028; art->set_rotation(rotation);
        Vector3 offset = art->get_position(); offset.y = std::abs(UtilityFunctions::sin(elapsed * 8.0 + double(e["id"]))) * .04; art->set_position(offset);
    } else if (previous_state == w.move) {
        Vector3 rotation = art->get_rotation(); rotation.z = 0; art->set_rotation(rotation);
        Vector3 offset = art->get_position(); offset.y = 0; art->set_position(offset);
    }
    if (state == w.attack) {
        Vector3 offset = art->get_position(); offset.x = -.12 * std::min(double(e.get(k.attack_flash, 0.0)) * 4.0, 1.0); art->set_position(offset);
    } else if (previous_state == w.attack) {
        Vector3 offset = art->get_position(); offset.x = 0; art->set_position(offset);
    }
    if (state != previous_state) { world->call(w.paper_state, model, state); pose.state=state; }
    double fraction = std::clamp(double(e[k.hp]) / std::max(double(spec[k.hp]), .001), 0.0, 1.0);
    double width = record->hp_width;
    if (fraction != pose.hp_fraction) {
        for (Node3D *bar : {record->fill, record->fill_back}) {
            Vector3 scale = bar->get_scale(); scale.x = width * fraction; bar->set_scale(scale);
            Vector3 offset = bar->get_position(); offset.x = (fraction - 1.) * width * .5; bar->set_position(offset);
        }
        model[k.hp_fraction] = fraction; pose.hp_fraction=fraction;
    }
    int64_t count = 0;
    auto append = [&](const Dictionary &batch, const Transform3D &transform, PaperFrontRenderBatch *queue) {
        if (queue && queue->enabled) queue->append_transform(transform);
        else { Array transforms = batch[k.transforms]; transforms.push_back(transform); }
        ++count;
    };
    Transform3D transform = root->get_global_transform();
    // GDScript can change the paper card during quality changes or pool reuse.
    // Resolve this dynamic batch from the current model, never a stale cache.
    const Dictionary paper_batch=model[w.paper_batch];
    append(paper_batch, transform * art->get_transform(),render_batch(paper_batch));
    append(record->shadow_batch, transform * record->shadow->get_transform(),record->shadow_queue);
    if (selected) append(record->ring_batch, transform * record->ring->get_transform(),record->ring_queue);
    if (selected || double(e.get(k.hit_flash, 0.0)) > 0) {
        Transform3D hp_transform = transform * record->hp->get_transform();
        const Array &bars=record->hp_bars, &batches=record->hp_batches;
        for (int64_t i = 0; i < bars.size(); ++i) {
            Object *object = bars[i]; append(batches[i], hp_transform * Object::cast_to<Node3D>(object)->get_transform(),record->hp_queues[i]);
        }
    }
    return count;
}
Dictionary sync_world_native(Object *world, const Dictionary &entities, Dictionary models, const Dictionary &selected,
    const Dictionary &map, const String &policy, double elapsed, double yaw, double capacity, double construction_time,
    const std::vector<Plane> &planes, const std::vector<double> &sides, const PoseKeys &k, const WorldKeys &w, WorldModelCache &cache, bool profile=false) {
    using Clock=std::chrono::steady_clock;
    auto stamp=Clock::now();
    int64_t lifecycle_ns=0, culling_ns=0, cache_ns=0, volume_ns=0, paper_ns=0, fallback_ns=0;
    auto record_stage=[&](int64_t &bucket) { if (profile) { auto now=Clock::now(); bucket+=std::chrono::duration_cast<std::chrono::nanoseconds>(now-stamp).count(); stamp=now; } };
    Array terrain = map["terrain"], heights = map["heights"]; int64_t map_size = map["size"];
    const double water_depth = String(map.get("mode", String())) == "dev" ? double(map.get("developer_water_depth", 2.65)) : 2.65;
    const bool performance = policy == w.performance;
    int64_t visible = 0, culled = 0, cached = 0, submitted = 0;
    // Tools can explicitly remove a public model and free its scene nodes.
    // Notice map-size changes before dereferencing retained renderer records.
    if (size_t(models.size())!=cache.by_id.size()) cache.clear();
    if (cache.ordered.empty() && !models.is_empty()) {
        // A script-path capture can move a model to the end of the public map.
        // Seed that order, rather than substituting entity insertion order.
        const Array model_ids=models.keys();
        for (int64_t i=0;i<model_ids.size();++i) {
            auto &entry=cache.get(int64_t(model_ids[i]));
            entry.model=models[model_ids[i]];
            entry.team=entry.model[w.team]; entry.scaffold=entry.model.get(w.scaffold,false);
            entry.record=(entry.scaffold || bool(entry.model.get(w.direct_skinned,false))) ? nullptr : render_record(entry.model,k);
        }
    }
    ++cache.frame;
    const Array ids = entities.keys();
    for (int64_t i = 0; i < ids.size(); ++i) {
        Variant id = ids[i]; Dictionary e = entities[id];
        bool scaffold=false;
        if (String(e[k.kind]) == w.building) {
            Variant construction=e.get(w.construction,Variant());
            scaffold=construction.get_type()==Variant::DICTIONARY && !Dictionary(construction).is_empty();
        }
        auto &entry=cache.get(int64_t(id));
        if (entry.model.is_empty()) {
            Variant existing=models.get(id,Variant());
            if (existing.get_type()!=Variant::DICTIONARY) { existing=world->call(w.create_entity,e); models[id]=existing; }
            entry.model=existing;
            entry.team=entry.model[w.team]; entry.scaffold=entry.model.get(w.scaffold,false);
            entry.record=(entry.scaffold || bool(entry.model.get(w.direct_skinned,false))) ? nullptr : render_record(entry.model,k);
        }
        if (entry.team!=int64_t(e[w.team]) || entry.scaffold!=scaffold) {
            pose_node(entry.model,k.root)->queue_free();
            entry.model=world->call(w.create_entity,e); models[id]=entry.model;
            entry.team=e[w.team]; entry.scaffold=scaffold;
            entry.record=(scaffold || bool(entry.model.get(w.direct_skinned,false))) ? nullptr : render_record(entry.model,k);
            entry.native_pose=false;
        }
        entry.seen=cache.frame;
        Dictionary &model=entry.model;
        PaperFrontRenderRecord *record=entry.record;
        if (record && !entry.native_pose) record->pose.load(model,k);
        record_stage(lifecycle_ns);
        // Team 0 owns this renderer. Keep hidden entities in the lifecycle
        // cache so shroud transitions neither respawn them nor emit death FX.
        // Old snapshots lacking visible_to remain visible until vision refresh.
        Variant visibility=e.get(w.visible_to, Variant());
        bool fog_hidden=visibility.get_type()!=Variant::NIL && (int64_t(visibility)&1)==0;
        Node3D *scene_root=record ? record->root : pose_node(model,k.root);
        if (fog_hidden) {
            model[w.fog_hidden]=true;
            model[w.view_culled]=true;
            scene_root->set_visible(false);
            ++culled;
            record_stage(culling_ns);
            continue;
        }
        if (bool(model.get(w.fog_hidden,false))) {
            model[w.fog_hidden]=false;
            scene_root->set_visible(true);
        }
        bool loaded = int64_t(e.get(k.transport_id, -1)) > 0 || int64_t(e.get(StringName("garrison_id"), -1)) >= 0;
        Vector2 p = e[k.pos];
        if (!loaded) {
            // Domain comes from the stable model recipe/spec cache. The naval
            // Use the same water sheet as MapData, including the shallow dev
            // harbor. Ordinary and historical maps retain their 2.65 depth.
            const Dictionary spec = record ? record->spec : Dictionary(model[k.spec]);
            const Array terrain_row=terrain[std::clamp<int64_t>(std::floor(p.y),0,map_size-1)];
            const bool naval = String(spec.get(w.domain, w.ground)) == w.naval && int64_t(terrain_row[std::clamp<int64_t>(std::floor(p.x),0,map_size-1)]) == 1;
            if (Vector2(model[w.last_terrain_pos]) != p) {
                model[k.terrain_height] = render_height(terrain, heights, map_size, p) - (naval ? water_depth : 0.0);
                model[w.last_terrain_pos] = p;
            }
            double flight = (record ? record->is_air : bool(model[k.is_air])) ? double(e.get(k.flight_height, spec.get(k.flight_height, 0.0))) : 0.0;
            Vector2 dimensions = record ? record->dimensions : Vector2(model[k.dimensions]);
            Vector3 center(p.x, double(model[k.terrain_height]) + flight + dimensions.y * .5, p.y);
            double radius = record ? record->cull_radius : double(model[w.cull_radius]);
            bool inside = true;
            for (size_t plane = 0; plane < planes.size(); ++plane) {
                if (double(planes[plane].distance_to(center)) * sides[plane] < -radius) { inside = false; break; }
            }
            if (!inside) {
                if (Vector2(model[k.last_pos]) != p) { (record ? record->root : pose_node(model,k.root))->set_position(Vector3(p.x, double(model[k.terrain_height]), p.y)); model[k.last_pos] = p; if (record) record->pose.position=p; }
                model[k.embarked] = false; model[w.view_culled] = true;
                if (bool(model.get(w.direct_skinned, false))) scene_root->set_visible(false);
                ++culled; record_stage(culling_ns); continue;
            }
            ++visible;
        }
        model[w.view_culled] = false;
        bool is_selected = selected.has(id);
        record_stage(culling_ns);
        if (!performance || scaffold || bool(model.get(w.direct_skinned,false))) { entry.native_pose=false; world->call(w.sync_entity, model, e, is_selected); record_stage(fallback_ns); continue; }
        bool volume = record->volumetric;
        // Constructing a 13-Variant signature and nested replay arrays costs
        // more than calculating these poses. Keep only the GPU upload cache.
        if (!entry.native_pose) model.erase(w.visual_signature);
        entry.native_pose=true;
        record_stage(cache_ns);
        if (volume) { submitted += update_volume_native(model, e, is_selected, yaw, elapsed, capacity, construction_time, k, record, false); record_stage(volume_ns); }
        else { submitted += update_paper_native(world, model, e, is_selected, elapsed, k, w, record); record_stage(paper_ns); }
    }
    for (auto &entry : cache.ordered) {
        if (entry.id<0 || entry.seen==cache.frame) continue;
        Dictionary &model=entry.model;
        if (bool(model.get(k.embarked,false)) || bool(model.get(w.fog_hidden,false))) pose_node(model,k.root)->queue_free();
        else world->call(w.start_death,model);
        models.erase(entry.id); cache.retire(entry);
    }
    cache.compact();
    Dictionary result;
    result["visible"] = visible; result["culled"] = culled; result["cached"] = cached; result["submitted"] = submitted;
    if (profile) {
        result["native_lifecycle_us"]=double(lifecycle_ns)/1000.; result["native_culling_us"]=double(culling_ns)/1000.; result["native_cache_us"]=double(cache_ns)/1000.;
        result["native_volume_us"]=double(volume_ns)/1000.; result["native_paper_us"]=double(paper_ns)/1000.; result["native_fallback_us"]=double(fallback_ns)/1000.;
    }
    return result;
}

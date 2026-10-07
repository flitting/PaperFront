// Pure derived-index construction. Same insertion order as Dictionary.values().
Dictionary rebuild_spatial_native(const Dictionary &entities, int64_t faction_count, const Dictionary &air_specs, const Dictionary &naval_specs) {
    const StringName id_key("id"), position_key("pos"), team_key("team"), hp_key("hp"),
        transport_key("transport_id"), kind_key("kind"), spec_key("spec"), airborne_key("airborne");
    const String unit_kind("unit");
    Dictionary spatial, combat, contact_buckets, contact_indices;
    Array team_spatial;
    team_spatial.resize(faction_count);
    for (int64_t team = 0; team < faction_count; ++team) team_spatial[team] = Dictionary();
    PackedInt64Array ids;
    PackedVector2Array positions;
    PackedInt32Array teams;
    PackedByteArray domains;
    ids.resize(entities.size()); positions.resize(entities.size());
    teams.resize(entities.size()); domains.resize(entities.size());
    // Mutable packed arrays are local to this call, so there are no COW copies.
    auto *ids_ptr = ids.ptrw(); auto *pos_ptr = positions.ptrw();
    auto *team_ptr = teams.ptrw(); auto *domain_ptr = domains.ptrw();
    Array records = entities.values();
    int64_t used = 0;
    auto append = [](Dictionary &map, Vector2i key, const Variant &value) {
        Variant old = map.get(key, Variant());
        Array bucket;
        if (old.get_type() == Variant::ARRAY) bucket = old;
        else map[key] = bucket;
        bucket.push_back(value);
    };
    for (int64_t i = 0; i < records.size(); ++i) {
        Dictionary e = records[i];
        if (double(e[hp_key]) <= 0 || int64_t(e.get(transport_key, -1)) > 0) continue;
        int64_t id = e[id_key], team = e[team_key];
        if (team < 0 || team >= faction_count) continue;
        Vector2 pos = e[position_key];
        bool unit = String(e[kind_key]) == unit_kind;
        bool air = unit && air_specs.has(e[spec_key]);
        bool naval = unit && naval_specs.has(e[spec_key]) && String(e.get(StringName("surface_domain"), "naval")) != "ground";
        int64_t slot = used++;
        contact_indices[id] = slot;
        ids_ptr[slot] = id; pos_ptr[slot] = pos; team_ptr[slot] = team; domain_ptr[slot] = air ? 2 : (naval ? 4 : 1);
        Vector2i cell(std::floor(pos.x / 8.0), std::floor(pos.y / 8.0));
        Dictionary team_buckets = team_spatial[team];
        append(team_buckets, cell, id); append(combat, cell, id); append(contact_buckets, cell, slot);
        if (unit && (!air || !bool(e.get(airborne_key, true))) && !naval) append(spatial, Vector2i(std::floor(pos.x / 2.0), std::floor(pos.y / 2.0)), e);
    }
    Dictionary result;
    result["spatial"] = spatial; result["combat"] = combat; result["contact_buckets"] = contact_buckets;
    result["contact_indices"] = contact_indices; result["team_spatial"] = team_spatial;
    result["ids"] = ids; result["positions"] = positions; result["teams"] = teams; result["domains"] = domains;
    result["used"] = used;
    return result;
}

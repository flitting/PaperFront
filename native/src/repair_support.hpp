#include <unordered_map>
void repair_support_native(const Dictionary &entities, const Dictionary &stations,
    const Dictionary &field, const Dictionary &specs, Array money, const Dictionary &air_specs,
    double delta, double cost) {
    const Variant kind_key{StringName("kind")}, spec_key{StringName("spec")}, hp_key{StringName("hp")}, id_key{StringName("id")},
        team_key{StringName("team")}, pos_key{StringName("pos")}, transport_key{StringName("transport_id")}, armor_key{StringName("armor_class")}, crushable_key{StringName("crushable")};
    struct Station { Vector2 position; double radius, rate; };
    std::unordered_map<int64_t,std::vector<Station>> local_stations;
    const Array teams=stations.keys();
    for (int64_t i=0;i<teams.size();++i) {
        const int64_t team=teams[i]; const Array rows=stations[team];
        auto &output=local_stations[team]; output.reserve(rows.size());
        for (int64_t j=0;j<rows.size();++j) { const Array row=rows[j]; output.push_back({Vector2(row[0]),double(row[1]),double(row[2])}); }
    }
    auto heal = [&](Dictionary e, double amount) {
        Dictionary spec = specs[e[spec_key]];
        int64_t team = e[team_key];
        double hp = e[hp_key];
        double healed = std::min(amount, double(spec[hp_key]) - hp);
        if (cost > 0) healed = std::min(healed, double(money[team]) / cost);
        e[hp_key] = hp + healed;
        money[team] = std::max(0.0, double(money[team]) - healed * cost);
    };
    Array values = entities.values();
    for (int64_t i = 0; i < values.size(); ++i) {
        Dictionary e = values[i];
        if (String(e[kind_key]) != "unit" || air_specs.has(e[spec_key]) || int64_t(e.get(transport_key, -1)) > 0 || double(e[hp_key]) <= 0) continue;
        double rate = field.get(e[id_key], 0.0);
        int64_t team = e[team_key];
        auto found=local_stations.find(team);
        if (found!=local_stations.end()) {
            const Vector2 position=e[pos_key];
            double station_rate=0.0;
            for (const Station &station:found->second) {
                // Keep the reference distance calculation and inclusive edge.
                if (double(position.distance_to(station.position))<=station.radius) station_rate=std::max(station_rate,station.rate);
            }
            // Resolve armor only for units actually covered by a stronger aura.
            if (station_rate>rate) {
                const Dictionary spec=specs[e[spec_key]];
                const String armor=spec.get(armor_key,bool(e[crushable_key]) ? "infantry" : "armored");
                if (armor=="armored") rate=station_rate;
            }
        }
        if (rate > 0) heal(e, rate * delta);
    }
    Array repair_ids = field.keys();
    for (int64_t i = 0; i < repair_ids.size(); ++i) {
        Variant id = repair_ids[i];
        if (!entities.has(id)) continue;
        Dictionary e = entities[id];
        if (String(e[kind_key]) == "building") heal(e, double(field[id]) * delta);
    }
}
struct TargetKeys {
    const Variant transport{StringName{"transport_id"}}, hp{StringName{"hp"}}, team{StringName{"team"}}, commands_key{StringName{"commands"}},
        kind{StringName{"kind"}}, target_key{StringName{"target"}}, spec{StringName{"spec"}};
};
bool can_target_native(const Dictionary &source, int64_t target, const Dictionary &entities,
    int64_t mask, const Dictionary &air_specs, const Dictionary &naval_specs, bool force, const TargetKeys &keys) {
    const Variant &transport=keys.transport, &hp=keys.hp, &team=keys.team, &commands_key=keys.commands_key,
        &kind=keys.kind, &target_key=keys.target_key, &spec=keys.spec;
    if (!mask || int64_t(source.get(transport, -1)) > 0) return false;
    Variant found = entities.get(target, Variant());
    if (found.get_type() != Variant::DICTIONARY) return false;
    Dictionary other = found;
    if (double(other[hp]) <= 0 || int64_t(other.get(transport, -1)) > 0) return false;
    if (!(int64_t(other.get(StringName("visible_to"), 255)) & (int64_t(1) << int64_t(source[team])))) return false;
    if (!force) {
        Array commands = source[commands_key];
        if (!commands.is_empty()) {
            Dictionary command = commands[0];
            if (String(command[kind]) == "force_attack") {
                int64_t requested = command[target_key];
                force = requested == target || requested == -1;
            }
        }
    }
    if (int64_t(other[team]) == int64_t(source[team]) && !force) return false;
    bool air = String(other.get(kind, "unit")) == "unit" && air_specs.has(other[spec]);
    bool naval = String(other.get(kind, "unit")) == "unit" && naval_specs.has(other[spec]);
    return (mask & (air ? 2 : (naval ? 4 : 1))) != 0;
}

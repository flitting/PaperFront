#include <unordered_map>
// Common unit state-machine execution. Navigation, special commands, air service,
// firing, damage settlement and ordering remain the existing simulation methods.
// Retain no PackedArray snapshots across callbacks: movement mutates those arrays.
struct UnitKeys {
    const Variant id{StringName{"id"}};
    const Variant radius{StringName{"radius"}};
    const Variant kind{StringName{"kind"}};
    const Variant spec{StringName{"spec"}};
    const Variant team{StringName{"team"}};
    const Variant hp{StringName{"hp"}};
    const Variant pos{StringName{"pos"}};
    const Variant state{StringName{"state"}};
    const Variant commands{StringName{"commands"}};
    const Variant target{StringName{"target"}};
    const Variant weapon{StringName{"weapon"}};
    const Variant range{StringName{"range"}};
    const Variant alpha{StringName{"alpha"}};
    const Variant turret_alpha{StringName{"turret_alpha"}};
    const Variant turret_target{StringName{"turret_target"}};
    const Variant auto_target{StringName{"auto_target"}};
    const Variant has_turret{StringName{"has_turret"}};
    const Variant art{StringName{"art"}};
    const Variant fire_while_moving{StringName{"fire_while_moving"}};
    const Variant turn_speed{StringName{"turn_speed"}};
    const Variant turret_turn_speed{StringName{"turret_turn_speed"}};
    const Variant cooldown{StringName{"cooldown"}};
    const Variant hit_flash{StringName{"hit_flash"}};
    const Variant attack_flash{StringName{"attack_flash"}};
    const Variant path_wait{StringName{"path_wait"}};
    const Variant motion{StringName{"motion"}};
    const Variant transport_id{StringName{"transport_id"}};
    const Variant emp_until{StringName{"emp_until"}};
    const Variant yield_goal{StringName{"yield_goal"}};
    const Variant harvest_override{StringName{"harvest_override"}};
    const Variant yield_until{StringName{"yield_until"}}, path{StringName{"path"}}, path_goal{StringName{"path_goal"}}, time{StringName{"time"}};
    const Variant ammo{StringName("ammo")}, flight_state{StringName("flight_state")}, home_airfield{StringName("home_airfield")},
        construct_remaining{StringName("construct_remaining")}, role{StringName("role")};
    const StringName _step_unit_after_service{"_step_unit_after_service"};
    const StringName _step_building{"_step_building"};
    const StringName _step_unit{"_step_unit"};
    const StringName _step_aircraft_service{"_step_aircraft_service"};
    const StringName _step_harvester{"_step_harvester"};
    const StringName _move_order{"_move_order"};
    const StringName _move_to{"_move_to"};
    const StringName _nearest_enemy{"_nearest_enemy"};
    const StringName _weapon_can_target{"_weapon_can_target"};
    const StringName _target_alive{"_target_alive"};
    const StringName _target_position{"_target_position"};
    const StringName _air_goal{"_air_goal"};
    const StringName _near_stand{"_near_stand"};
    const StringName _combat_approach{"_combat_approach"};
    const StringName _fire{"_fire"};
    const StringName _finish_command{"_finish_command"};
    const StringName _lost_target_order{"_lost_target_order"};
    const String unit{"unit"}, building{"building"}, idle{"idle"}, waiting{"waiting"}, unreachable{"unreachable"}, move{"move"}, attack{"attack"}, force_attack{"force_attack"}, attack_move{"attack_move"}, patrol{"patrol"}, tank{"tank"}, assault{"assault"}, harvester_suffix{"_harvester"};
};
// Definitions are constant during a simulation tick. Resolve repeated optional
// fields once per encountered specification, then discard the cache after the
// tick so edits between ticks (including loaded rules) are observed immediately.
struct UnitSpecView {
    String weapon;
    double reach=0.0, turn_speed=360.0, turret_turn_speed=360.0;
    bool turret=false, mobile_fire=false, has_mask=false;
    int64_t mask=0;
};
struct UnitSpecHash { size_t operator()(const String &value) const { return value.hash(); } };
struct UnitTickContext {
    Object *sim;
    Dictionary entities, specs, weapons, air_specs, naval_specs, masks;
    double delta, fire_angle;
    const UnitKeys &k;
    const TargetKeys &target_keys;

    mutable std::unordered_map<String, UnitSpecView, UnitSpecHash> spec_views;
    const UnitSpecView &spec_view(const String &id) const {
        auto found=spec_views.find(id);
        if (found!=spec_views.end()) return found->second;
        const Dictionary data=specs[id];
        UnitSpecView view;
        view.weapon=data.get(k.weapon,String());
        if (!view.weapon.is_empty()) { const Dictionary weapon=weapons[view.weapon]; view.reach=weapon[k.range]; }
        const String art=data.get(k.art,String());
        view.turret=data.has(k.has_turret) ? bool(data[k.has_turret]) : art==k.tank || art==k.assault;
        view.mobile_fire=view.turret && bool(data.get(k.fire_while_moving,true));
        view.turn_speed=data.get(k.turn_speed,360);
        view.turret_turn_speed=data.get(k.turret_turn_speed,view.turn_speed);
        view.has_mask=masks.has(id);
        if (view.has_mask) view.mask=masks[id];
        return spec_views.emplace(id,view).first->second;
    }

    bool loaded(const Dictionary &e) const { return int64_t(e.get(k.transport_id, -1)) > 0; }
    bool air(const Dictionary &e) const { return String(e.get(k.kind, k.unit)) == k.unit && air_specs.has(e[k.spec]); }
    bool naval(const Dictionary &e) const { return String(e.get(k.kind, k.unit)) == k.unit && naval_specs.has(e[k.spec]); }
    bool ordinary_airborne(const Dictionary &e) const {
        if (String(e.get(k.flight_state,String()))!="airborne" || int64_t(e.get(k.ammo,0))<=0) return false;
        Variant found=entities.get(e.get(k.home_airfield,-1),Variant());
        if (found.get_type()!=Variant::DICTIONARY) return false;
        const Dictionary field=found;
        if (String(field[k.kind])!=k.building || int64_t(field[k.team])!=int64_t(e[k.team]) || !(double(field[k.hp])>0) || !(double(field[k.construct_remaining])<=0)) return false;
        const Dictionary info=specs[field[k.spec]];
        return String(info.get(k.role,String()))=="airfield";
    }
    bool has_turret(const UnitSpecView &spec) const { return spec.turret; }
    bool move_fire(const UnitSpecView &spec) const { return spec.mobile_fire; }
    bool alive(int64_t target) const {
        if (target < 0) return bool(sim->call(k._target_alive, target));
        Variant found = entities.get(target, Variant());
        if (found.get_type() != Variant::DICTIONARY) return false;
        const Dictionary other = found;
        return double(other[k.hp]) > 0.0 && !loaded(other);
    }
    Vector2 target_position(int64_t target) const {
        if (target < 0) return Vector2(sim->call(k._target_position, target));
        if (!entities.has(target)) return Vector2();
        Dictionary other = entities[target];
        return other[k.pos];
    }
    bool can_target(const Dictionary &e, int64_t target, const UnitSpecView &spec) const {
        if (target < 0 || !spec.has_mask) return bool(sim->call(k._weapon_can_target, e, target));
        return can_target_native(e, target, entities, spec.mask, air_specs, naval_specs, false, target_keys);
    }
    bool valid_target(const Dictionary &e,int64_t target,const UnitSpecView &spec) const {
        // Positive entity validation already checks health and transport.
        // Negative scenery IDs keep their original simulation liveness check.
        return (target>=0 || alive(target)) && can_target(e,target,spec);
    }
    void turn(Dictionary e, const UnitSpecView &spec, double wanted, bool turret) const {
        const double current = turret ? double(e.get(k.turret_alpha, e[k.alpha])) : double(e[k.alpha]);
        const double difference = UtilityFunctions::wrapf(wanted - current, -180., 180.);
        const double speed = turret ? spec.turret_turn_speed : spec.turn_speed;
        e[turret ? k.turret_alpha : k.alpha] = UtilityFunctions::wrapf(current + std::clamp(difference, -speed * delta, speed * delta), -180., 180.);
    }
    void turret_forward(Dictionary e, const UnitSpecView &spec) const {
        e[k.turret_target] = -1;
        turn(e, spec, double(e[k.alpha]), true);
    }
    void fire(Dictionary e, int64_t target) const {
        // Same short-circuit as _fire; the original method owns all validation
        // and shot creation whenever the cooldown actually permits a shot.
        if (!(double(e[k.cooldown]) > 0.0)) sim->call(k._fire, e, target);
    }
    void aim(Dictionary e, const UnitSpecView &spec, int64_t target) const {
        if (!valid_target(e,target,spec)) { turret_forward(e, spec); return; }
        aim_validated(e,spec,target);
    }
    void aim_validated(Dictionary e,const UnitSpecView &spec,int64_t target) const {
        e[k.turret_target] = target;
        const double wanted = UtilityFunctions::rad_to_deg((target_position(target) - Vector2(e[k.pos])).angle());
        turn(e, spec, wanted, true);
        if (double(e[k.motion]) > 0.0 && !move_fire(spec)) return;
        if (std::abs(UtilityFunctions::wrapf(wanted - double(e[k.turret_alpha]), -180., 180.)) <= fire_angle) fire(e, target);
    }
    void mobile(Dictionary e, const UnitSpecView &spec) const {
        const String &weapon_id = spec.weapon;
        if (weapon_id.is_empty()) { turret_forward(e, spec); return; }
        const double reach = spec.reach;
        int64_t target = e[k.auto_target];
        const bool retained=valid_target(e,target,spec) && !(target_position(target).distance_to(Vector2(e[k.pos]))>reach);
        if (!retained) target = sim->call(k._nearest_enemy, e, reach);
        e[k.auto_target] = target;
        if (target >= 0) {
            if (retained) aim_validated(e,spec,target);
            else aim(e,spec,target);
        }
        else turret_forward(e, spec);
    }
    void engage(Dictionary e, const UnitSpecView &spec, int64_t target, bool pursue, bool validated=false) const {
        if (!validated && !can_target(e, target, spec)) return;
        const String &weapon_id = spec.weapon;
        if (weapon_id.is_empty()) { e[k.state] = k.waiting; return; }
        const Vector2 target_pos = target_position(target), position = e[k.pos];
        const double reach = spec.reach;
        if (double(position.distance_to(target_pos)) > reach) {
            if (pursue) {
                const Vector2 goal = sim->call(k._combat_approach, e, target_pos, reach);
                if (goal.is_finite()) sim->call(k._move_to, e, goal, delta);
                else e[k.state] = k.unreachable;
            }
            if (has_turret(spec)) aim(e, spec, target);
            return;
        }
        e[k.state] = k.idle;
        // No movement or gameplay callback occurred since validation above.
        if (has_turret(spec)) aim_validated(e, spec, target);
        else {
            const double wanted = UtilityFunctions::rad_to_deg((target_pos - Vector2(e[k.pos])).angle());
            turn(e, spec, wanted, false);
            if (std::abs(UtilityFunctions::wrapf(wanted - double(e[k.alpha]), -180., 180.)) <= fire_angle) fire(e, target);
        }
    }
    void unit(Dictionary e) const {
        if (loaded(e)) return;
        if (double(e.get(k.emp_until, 0.0)) > double(sim->get(k.time))) {
            e[k.state] = String("emp");
            return;
        }
        if (air(e) && !ordinary_airborne(e) && bool(sim->call(k._step_aircraft_service, e, delta))) return;
        const String spec_id = e[k.spec];
        const UnitSpecView &spec = spec_view(spec_id);
        Vector2 yielding = e.get(k.yield_goal, Vector2(INFINITY, INFINITY));
        if (yielding.is_finite()) {
            const double time = sim->get(k.time);
            if (time >= double(e.get(k.yield_until, time + 3.0))) {
                e[k.yield_goal] = Vector2(INFINITY, INFINITY);
                Array path = e[k.path]; path.clear();
                e[k.path_goal] = Vector2(INFINITY, INFINITY); e[k.path_wait] = 0.0;
                yielding = Vector2(INFINITY, INFINITY);
            } else {
                if (!e.has(k.yield_until)) e[k.yield_until] = time + 3.0;
                if (bool(sim->call(k._move_to, e, yielding, delta))) {
                    e[k.yield_goal] = Vector2(INFINITY, INFINITY);
                    Array path = e[k.path]; path.clear();
                    e[k.path_goal] = Vector2(INFINITY, INFINITY); e[k.path_wait] = 0.0;
                }
                if (has_turret(spec)) {
                    const Array commands = e[k.commands];
                    const Dictionary command = commands.is_empty() ? Dictionary() : Dictionary(commands[0]);
                    const String kind = command.get(k.kind, String());
                    if (move_fire(spec) && (kind == k.attack || kind == k.attack_move)) {
                        if (kind == k.attack && can_target(e, int64_t(command[k.target]), spec)) aim(e, spec, int64_t(command[k.target]));
                        else mobile(e, spec);
                    } else turret_forward(e, spec);
                }
                return;
            }
        }
        const Array commands = e[k.commands];
        const Dictionary command = commands.is_empty() ? Dictionary() : Dictionary(commands[0]);
        const String kind = command.get(k.kind, String());
        // Rare jobs keep the original implementation. Air service has already
        // executed once, so enter the reference state machine after that stage.
        if ((spec_id.ends_with(k.harvester_suffix) && commands.is_empty() && !bool(e[k.harvest_override]))
            || (!command.is_empty() && kind != k.move && kind != k.attack && kind != k.attack_move && kind != k.patrol && kind != k.force_attack)
            || (kind == k.force_attack && int64_t(command[k.target]) == -1)) {
            sim->call(k._step_unit_after_service, e, delta);
            return;
        }
        if (!command.is_empty()) {
            if (kind == k.move) {
                if (bool(sim->call(k._move_order, e, command, delta))) sim->call(k._finish_command, e);
                if (has_turret(spec)) turret_forward(e, spec);
                return;
            }
            if (kind == k.attack || kind == k.force_attack) {
                const int64_t target = command[k.target];
                if (!valid_target(e,target,spec)) {
                    if (bool(sim->call(k._lost_target_order, e, target))) return;
                    sim->call(k._finish_command, e);
                    if (has_turret(spec)) turret_forward(e, spec);
                    return;
                }
                engage(e, spec, target, true, true);
                return;
            }
            if (kind == k.attack_move || kind == k.patrol) {
                if (move_fire(spec)) {
                    const bool arrived = sim->call(k._move_order, e, command, delta);
                    mobile(e, spec);
                    if (arrived) sim->call(k._finish_command, e);
                    return;
                }
                const String &weapon_id = spec.weapon;
                int64_t target = e[k.auto_target];
                if (!valid_target(e,target,spec) || target_position(target).distance_to(Vector2(e[k.pos])) > 14.0) target = -1;
                if (target < 0 && !weapon_id.is_empty()) {
                    target = sim->call(k._nearest_enemy, e, spec.reach + 2.0);
                }
                e[k.auto_target] = target;
                if (target >= 0) engage(e, spec, target, true);
                else if (bool(sim->call(k._move_order, e, command, delta))) sim->call(k._finish_command, e);
                return;
            }
        }
        const String &weapon_id = spec.weapon;
        e[k.state] = k.idle;
        if (!weapon_id.is_empty()) {
            const int64_t target = sim->call(k._nearest_enemy, e, spec.reach);
            if (target >= 0) engage(e, spec, target, false);
            else if (has_turret(spec)) turret_forward(e, spec);
        }
    }
};
void step_entities_native(Object *sim, const Dictionary &entities, const Dictionary &specs,
    const Dictionary &weapons, const Dictionary &air_specs, const Dictionary &naval_specs, const Dictionary &masks,
    const Array &multipliers, double delta, double fire_angle, const UnitKeys &k, const TargetKeys &target_keys) {
    UnitTickContext context{sim, entities, specs, weapons, air_specs, naval_specs, masks, delta, fire_angle, k, target_keys};
    const Array ids = entities.keys();
    for (int64_t i = 0; i < ids.size(); ++i) {
        const Variant id = ids[i];
        if (!entities.has(id)) continue;
        Dictionary e = entities[id];
        if (double(e[k.hp]) <= 0.0) continue;
        for (const Variant *field : {&k.cooldown, &k.hit_flash, &k.attack_flash, &k.path_wait}) {
            const Variant &current=e[*field];
            const double value=current;
            // Preserve normalization of integer, negative-zero and invalid
            // values; initialized floating zero timers need no repeated write.
            if (current.get_type()!=Variant::FLOAT || value!=0.0 || std::signbit(value)) e[*field]=std::max(0.0,value-delta);
        }
        e[k.motion] = 0.0;
        if (String(e[k.kind]) == k.building) sim->call(k._step_building, e, delta, multipliers[int64_t(e[k.team])]);
        else context.unit(e);
    }
}

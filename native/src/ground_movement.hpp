// Exact ground movement hot path. The simulation still owns paths, collision
// buckets and entity dictionaries. Budgeted detours/yield requests use the same
// script helpers as the reference implementation, in the same insertion order.
struct MovementKeys {
    const Variant id{StringName{"id"}}, radius{StringName{"radius"}}, pos{StringName{"pos"}}, spec{StringName{"spec"}}, team{StringName{"team"}}, hp{StringName{"hp"}},
        state{StringName{"state"}}, stuck{StringName{"stuck"}}, time{StringName{"time"}}, movement_retry_at{StringName{"movement_retry_at"}},
        commands{StringName{"commands"}}, path{StringName{"path"}}, path_goal{StringName{"path_goal"}}, path_wait{StringName{"path_wait"}},
        unreachable_notice{StringName{"unreachable_notice"}}, progress_anchor{StringName{"progress_anchor"}}, progress_clock{StringName{"progress_clock"}},
        avoid_until{StringName{"avoid_until"}}, avoid_dir{StringName{"avoid_dir"}}, reversing{StringName{"reversing"}}, yield_goal{StringName{"yield_goal"}},
        alpha{StringName{"alpha"}}, motion{StringName{"motion"}}, speed{StringName{"speed"}}, turn_speed{StringName{"turn_speed"}}, can_crush{StringName{"can_crush"}},
        crushable{StringName{"crushable"}}, kind{StringName{"kind"}}, target{StringName{"target"}}, goal{StringName{"goal"}}, revision{StringName{"revision"}}, valid{StringName{"valid"}};
    const StringName _nav_dirty{"_nav_dirty"}, _plan_was_deferred{"_plan_was_deferred"}, _spec_cache{"_spec_cache"},
        _goal_standing_cache{"_goal_standing_cache"}, _static_geometry_revision{"_static_geometry_revision"},
        _path_between{"_path_between"}, _notice{"_notice"}, _movement_detour{"_movement_detour"},
        _request_movement_yield{"_request_movement_yield"}, _spatial_move{"_spatial_move"}, _update_contact{"_update_contact"};
    const String idle{"idle"}, waiting{"waiting"}, unreachable{"unreachable"}, move{"move"}, force_move{"force_move"};
};
struct GroundMovement {
    Object *sim;
    GeometryQueries &geometry;
    const MovementKeys &k;
    bool crush(const Dictionary &e, const Dictionary &other) const {
        if (!bool(e[k.can_crush]) || !bool(other[k.crushable])) return false;
        if (e[k.team] != other[k.team]) return true;
        const Array commands = e[k.commands];
        if (commands.is_empty()) return false;
        const Dictionary command = commands[0];
        return String(command[k.kind]) == k.force_move && int64_t(command[k.target]) == int64_t(other[k.id]);
    }
    bool clear(Dictionary e, Vector2 start, Vector2 next, bool request_yield) const {
        const double radius = e[k.radius];
        const int64_t id = e[k.id];
        if (!geometry.segment_static(start, next, radius, id)) return false;
        const Array local = geometry.local_neighbors(next);
        for (int64_t i = 0; i < local.size(); ++i) {
            const Dictionary other = local[i];
            if (int64_t(other[k.id]) == id || double(other[k.hp]) <= 0.0) continue;
            const double combined = radius + double(other[k.radius]) + .02;
            const Vector2 point = other[k.pos];
            const double after = next.distance_squared_to(point), before = start.distance_squared_to(point);
            if (after >= combined * combined) continue;
            if (before < combined * combined && after > before + .00001) continue;
            if (crush(e, other)) continue;
            if (request_yield) sim->call(k._request_movement_yield, e, other, start, next);
            return false;
        }
        return true;
    }
    void settle(Dictionary e, Vector2 next) const {
        if (!bool(e[k.can_crush])) return;
        const Array local = geometry.local_neighbors(next);
        for (int64_t i = 0; i < local.size(); ++i) {
            Dictionary other = local[i];
            const double combined = double(e[k.radius]) + double(other[k.radius]);
            if (crush(e, other) && double(next.distance_squared_to(Vector2(other[k.pos]))) < combined * combined) {
                other[k.hp] = 0.0;
                sim->call(k._update_contact, other);
            }
        }
    }
    bool goal_standing(const Dictionary &e, Vector2 goal, double radius) const {
        Dictionary cache = sim->get(k._goal_standing_cache);
        const int64_t id = e[k.id], revision = sim->get(k._static_geometry_revision);
        const Variant previous = cache.get(id, Variant());
        if (previous.get_type() == Variant::DICTIONARY) {
            const Dictionary old = previous;
            if (!old.is_empty() && Vector2(old[k.goal]) == goal && double(old[k.radius]) == radius && int64_t(old[k.revision]) == revision) return old[k.valid];
        }
        const bool valid = geometry.standing(goal, radius, id, false);
        Dictionary entry; entry[k.goal] = goal; entry[k.radius] = radius; entry[k.revision] = revision; entry[k.valid] = valid;
        cache[id] = entry;
        return valid;
    }
    // Matches Geometry2D::get_closest_point_to_segment, including float order.
    static Vector2 closest(Vector2 point, Vector2 start, Vector2 end) {
        Vector2 direction = end - start;
        const real_t length = direction.length_squared();
        if (length < 1e-20f) return start;
        const real_t distance = direction.dot(point - start) / length;
        if (distance < 0) return start;
        if (distance > 1) return end;
        return start + direction * distance;
    }
    bool move(Dictionary e, Vector2 goal, double delta) const {
        const double radius = e[k.radius], time = sim->get(k.time);
        const int64_t id = e[k.id];
        if (time < double(e.get(k.movement_retry_at, 0))) { e[k.state] = k.waiting; return false; }
        if (!goal_standing(e, goal, radius)) {
            const Vector2 replacement = geometry.near_stand(goal, radius, id, 4.0, false);
            if (replacement.is_finite()) {
                Array commands = e[k.commands];
                if (!commands.is_empty()) {
                    Dictionary command = commands[0];
                    if (Vector2(command[k.pos]).is_equal_approx(goal)) command[k.pos] = replacement;
                }
                goal = replacement;
            } else { e[k.movement_retry_at] = time + 1.0; e[k.state] = k.waiting; return false; }
        }
        const Vector2 original = e[k.pos];
        if (double(original.distance_to(goal)) <= std::max(.25, radius * .4)) { e[k.state] = k.idle; e[k.stuck] = 0.0; return true; }
        if (bool(sim->get(k._nav_dirty))) { e[k.state] = k.waiting; return false; }
        Array path = e[k.path];
        if (Vector2(e[k.path_goal]).distance_to(goal) > 1.0 || path.is_empty()) {
            if (double(e[k.path_wait]) > 0) { e[k.state] = k.waiting; return false; }
            const Array planned = sim->call(k._path_between, original, goal, radius, id);
            if (bool(sim->get(k._plan_was_deferred))) { e[k.state] = k.waiting; return false; }
            e[k.path] = planned; path = planned; e[k.path_goal] = goal; e[k.path_wait] = 2.0 + double(id % 7) * .07;
            if (path.is_empty()) {
                e[k.state] = k.unreachable;
                if (!bool(e.get(k.unreachable_notice, false))) {
                    e[k.unreachable_notice] = true;
                    if (int64_t(e[k.team]) == 0) sim->call(k._notice, String::utf8("暂时没有可用路线，单位稍后重试"));
                }
                return false;
            }
            e[k.unreachable_notice] = false;
        }
        while (path.size() > 1) {
            const Vector2 first = path[0], following = path[1];
            const bool passed = (original - first).dot(following - first) > 0 && double(closest(original, first, following).distance_to(original)) < radius + .45;
            if ((double(original.distance_to(first)) < std::max(.45, radius) || passed) && geometry.segment_static(original, following, radius, id)) path.pop_front();
            else break;
        }
        while (!path.is_empty() && original.distance_to(Vector2(path[0])) < .2) {
            if (path.size() > 1 && !geometry.segment_static(original, path[1], radius, id)) break;
            path.pop_front();
        }
        if (path.is_empty()) return original.distance_to(goal) < .4;
        if (!e.has(k.progress_anchor)) e[k.progress_anchor] = original;
        const Vector2 anchor = e[k.progress_anchor];
        const double progress = double(e.get(k.progress_clock, 0.0)) + delta;
        e[k.progress_clock] = progress;
        if (progress > 2.5) {
            e[k.progress_clock] = 0.0; e[k.progress_anchor] = original;
            if (anchor.distance_to(original) < .65) {
                path.clear(); e[k.path_wait] = 0.0; e[k.stuck] = std::max(double(e[k.stuck]), 2.5); return false;
            }
        }
        const Dictionary specs = sim->get(k._spec_cache), spec = specs[e[k.spec]];
        const Vector2 waypoint = path[0], direction = (waypoint - original).normalized();
        double stride = std::min(double(spec[k.speed]) * delta, double(original.distance_to(waypoint)));
        stride *= geometry.walking_scale(original, radius);
        Vector2 next = original + direction * stride;
        bool can_move = clear(e, original, next, true);
        if (can_move) { e[k.avoid_until] = 0.0; if (!Vector2(e.get(k.yield_goal, Vector2(INFINITY, INFINITY))).is_finite()) e[k.reversing] = false; }
        else if (time < double(e.get(k.avoid_until, 0))) {
            const Vector2 candidate = original + Vector2(e[k.avoid_dir]) * stride;
            if (clear(e, original, candidate, false)) { next = candidate; can_move = true; }
        }
        if (!can_move) {
            const Vector2 candidate = sim->call(k._movement_detour, e, original, direction, stride);
            if (candidate.is_finite()) { next = candidate; can_move = true; }
        }
        if (can_move) {
            double wanted = UtilityFunctions::rad_to_deg((next - original).angle());
            if (radius > .5 && bool(e.get(k.reversing, false)) && (Vector2(e.get(k.yield_goal, Vector2(INFINITY, INFINITY))).is_finite() || time < double(e.get(k.avoid_until, 0)))) wanted = UtilityFunctions::wrapf(wanted + 180, -180, 180);
            const double current = e[k.alpha], speed = spec.get(k.turn_speed, 360);
            const double difference = UtilityFunctions::wrapf(wanted - current, -180., 180.);
            const double alpha = UtilityFunctions::wrapf(current + std::clamp(difference, -speed * delta, speed * delta), -180., 180.);
            e[k.alpha] = alpha;
            if (std::abs(UtilityFunctions::wrapf(wanted - alpha, -180., 180.)) > (radius > .5 ? 10.0 : 25.0)) {
                Vector2 forward = Vector2::from_angle(UtilityFunctions::deg_to_rad(alpha));
                if (bool(e.get(k.reversing, false)) && (Vector2(e.get(k.yield_goal, Vector2(INFINITY, INFINITY))).is_finite() || time < double(e.get(k.avoid_until, 0)))) forward = -forward;
                const Vector2 turning_step = original + forward * stride * .55;
                if (forward.dot((next - original).normalized()) > .15 && clear(e, original, turning_step, false) && bool(sim->call(StringName("_turning_connector_clear"), e, turning_step, waypoint))) next = turning_step;
                else {
                    e[k.state] = k.waiting; e[k.stuck] = double(e[k.stuck]) + delta;
                    if (time < double(e.get(k.avoid_until, 0))) e[k.avoid_until] = time + .55;
                    return false;
                }
            }
        }
        if (can_move) {
            settle(e, next); e[k.pos] = next; sim->call(k._spatial_move, e, original, next);
            e[k.motion] = original.distance_to(next); e[k.state] = k.move; e[k.stuck] = 0.0;
        } else {
            e[k.state] = k.waiting; e[k.stuck] = double(e[k.stuck]) + .2;
            e[k.movement_retry_at] = time + .18 + double(id % 5) * .015;
            if (double(e[k.stuck]) > 2.0 && double(e[k.path_wait]) <= 0.0) { path.clear(); e[k.path_wait] = 1.0; }
        }
        return false;
    }
};

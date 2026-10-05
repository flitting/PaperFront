// Exact collision-query kernels. Inputs are live Dictionaries/Arrays; the flat
// terrain mask is immutable during a tick. No navigation decisions are skipped.
struct GeometryKeys {
    const Variant hp{StringName{"hp"}}, pos{StringName{"pos"}}, half{StringName{"half"}}, id{StringName{"id"}}, radius{StringName{"radius"}},
        spec{StringName{"spec"}}, size{StringName{"size"}}, role{StringName{"role"}}, alive{StringName{"alive"}}, bounds{StringName{"bounds"}};
    const String barricade{"barricade"};
};
class GeometryQueries {
    int64_t size = 0;
    bool measurement_enabled=false;
    int64_t measured_queries=0,measured_ns=0,measured_rectangles=0;
    Array terrain, heights, bridges, mines;
    PackedByteArray flat;
    Dictionary ruins, buildings, mine_buckets, spatial, neighbors, specs;
    GeometryKeys k;
    static Vector2i bucket(Vector2 pos) { return Vector2i(std::floor(pos.x / 2.0), std::floor(pos.y / 2.0)); }
    static Array at(const Dictionary &map, Vector2i key) {
        Variant result = map.get(key, Variant());
        return result.get_type() == Variant::ARRAY ? Array(result) : Array();
    }
    bool in_bounds(Vector2 p) const { return p.x >= 0 && p.y >= 0 && p.x < size && p.y < size; }
    int64_t cell_type(Vector2 p) const {
        Array row = terrain[std::clamp<int64_t>(std::floor(p.y), 0, size - 1)];
        return row[std::clamp<int64_t>(std::floor(p.x), 0, size - 1)];
    }
    bool land(Vector2 p) const {
        if (!in_bounds(p)) return false;
        int64_t type = cell_type(p);
        if (type == 4) return false;
        if (type != 1) return true;
        int64_t found = -1;
        for (int64_t i = 0; i < bridges.size(); ++i) {
            Dictionary bridge = bridges[i]; Array bounds = bridge[k.bounds];
            if (p.x >= double(bounds[0]) && p.y >= double(bounds[1]) && p.x < double(bounds[0]) + double(bounds[2]) && p.y < double(bounds[1]) + double(bounds[3])) { found = bridge[k.id]; break; }
        }
        if (found < 0) return false;
        for (int64_t i = 0; i < bridges.size(); ++i) { Dictionary bridge = bridges[i]; if (int64_t(bridge[k.id]) == found) return bridge[k.alive]; }
        return false;
    }
    double height(Vector2 p) const {
        int64_t x = std::clamp<int64_t>(std::floor(p.x), 0, size - 1), z = std::clamp<int64_t>(std::floor(p.y), 0, size - 1);
        Array row = heights[z]; double level = row[x];
        if (cell_type(p) == 2) {
            double fraction = p.y - (z + .5);
            int64_t next = z + (fraction >= 0 ? 1 : -1);
            if (next >= 0 && next < size) {
                Array next_row = heights[next]; double next_level = next_row[x];
                if (std::abs(next_level - level) <= .75) return UtilityFunctions::lerpf(level, next_level, std::abs(fraction));
            }
        }
        return level;
    }
    bool fast_flat(Vector2 p, double radius) const {
        return radius <= .99 && in_bounds(p) && flat[int64_t(std::floor(p.y)) * size + int64_t(std::floor(p.x))] == 1;
    }
    static bool circle_rect(Vector2 p, double radius, Vector2 center, Vector2 half) {
        Vector2 closest = p.clamp(center - half, center + half);
        return double(p.distance_squared_to(closest)) < radius * radius + .00001;
    }
    static bool crosses_rect(Vector2 start, Vector2 end, Vector2 low, Vector2 high) {
        const Vector2 direction = end-start;
        double first=0.0,last=1.0;
        for (int axis=0;axis<2;++axis) {
            if (std::abs(double(direction[axis]))<.000001) {
                if (start[axis]<low[axis] || start[axis]>high[axis]) return false;
            } else {
                const double a=(double(low[axis])-double(start[axis]))/direction[axis],b=(double(high[axis])-double(start[axis]))/direction[axis];
                first=std::max(first,std::min(a,b));last=std::min(last,std::max(a,b));
                if(first>last)return false;
            }
        }
        return true;
    }
    static bool swept_circle_rect(Vector2 start, Vector2 end, double radius, Vector2 center, Vector2 half) {
        const double threshold=radius*radius+.00001,padded=std::sqrt(threshold);
        const Rect2 rectangle(center-half,half*2.0);
        const Vector2 low=rectangle.position,high=rectangle.get_end();
        const Vector2 pad(padded,padded),capsule_low=Vector2(std::min(start.x,end.x),std::min(start.y,end.y))-pad,
            capsule_high=Vector2(std::max(start.x,end.x),std::max(start.y,end.y))+pad;
        if(capsule_high.x<low.x || capsule_high.y<low.y || capsule_low.x>high.x || capsule_low.y>high.y)return false;
        const Vector2 actual_half=rectangle.size*.5,actual_center=rectangle.position+actual_half;
        if (crosses_rect(start,end,low,high) || circle_rect(start,radius,actual_center,actual_half) || circle_rect(end,radius,actual_center,actual_half)) return true;
        const Vector2 direction=end-start;
        const double length_squared=direction.length_squared();
        const Vector2 corners[]={low,high,Vector2(low.x,high.y),Vector2(high.x,low.y)};
        for (Vector2 corner:corners) {
            const double t=length_squared>0.0?std::clamp(double((corner-start).dot(direction))/length_squared,0.0,1.0):0.0;
            const Vector2 closest=start+direction*t;
            if(double(corner.distance_squared_to(closest))<threshold)return true;
        }
        return false;
    }
    static Dictionary segment_bucket_keys(Vector2 start,Vector2 end,double padding) {
        Dictionary keys;
        const int checks=std::max(1,int(std::ceil(double(start.distance_to(end)))));
        const Vector2 pad(padding,padding);
        for(int n=0;n<=checks;++n) {
            const Vector2 point=start.lerp(end,double(n)/checks);
            const Vector2i first=bucket(point-pad),last=bucket(point+pad);
            for(int z=first.y;z<=last.y;++z)for(int x=first.x;x<=last.x;++x)keys[Vector2i(x,z)]=true;
        }
        return keys;
    }
    bool segment_obstacles_clear(Vector2 start,Vector2 end,double radius,int64_t ignore) {
        const double clearance=radius+.02,reach=std::sqrt(clearance*clearance+.00001)+.5;
        const Array keys=segment_bucket_keys(start,end,std::max(0.0,reach-2.0)).keys();
        Dictionary checked;
        for(int64_t j=0;j<keys.size();++j) {
            const Array local=at(ruins,keys[j]);
            for(int64_t i=0;i<local.size();++i) {
                const Dictionary ruin=local[i];const Variant id=ruin[k.id];
                if(checked.has(id))continue;checked[id]=true;
                if(double(ruin[k.hp])<=0)continue;
                if(measurement_enabled)++measured_rectangles;
                if(swept_circle_rect(start,end,clearance,ruin[k.pos],ruin[k.half]))return false;
            }
        }
        checked.clear();
        for(int64_t j=0;j<keys.size();++j) {
            const Array local=mines.size()<=8?mines:at(mine_buckets,keys[j]);
            for(int64_t i=0;i<local.size();++i) {
                const Dictionary mine=local[i];const Variant id=mine[k.pos];
                if(checked.has(id))continue;checked[id]=true;
                if(measurement_enabled)++measured_rectangles;
                if(swept_circle_rect(start,end,clearance,mine[k.pos],Vector2(.55,.55)))return false;
            }
        }
        checked.clear();
        const Array building_keys=segment_bucket_keys(start,end,std::max(0.0,reach-1.1)).keys();
        for(int64_t j=0;j<building_keys.size();++j) {
            const Array local=at(buildings,building_keys[j]);
            for(int64_t i=0;i<local.size();++i) {
                const Dictionary e=local[i];const Variant id=e[k.id];
                if(checked.has(id))continue;checked[id]=true;
                if(int64_t(id)==ignore || double(e[k.hp])<=0)continue;
                const Dictionary spec=specs[e[k.spec]];
                if(radius<=.5 && String(spec.get(k.role,String()))==k.barricade)continue;
                const double half=double(spec[k.size])*.5;
                if(measurement_enabled)++measured_rectangles;
                if(swept_circle_rect(start,end,clearance,e[k.pos],Vector2(half,half)))return false;
            }
        }
        return true;
    }

public:
    void begin_measurement(bool enabled) { measurement_enabled=enabled;measured_queries=0;measured_ns=0;measured_rectangles=0; }
    Dictionary measurement() const {
        Dictionary answer;answer["queries"]=measured_queries;answer["microseconds"]=measured_ns/1000;answer["rectangles"]=measured_rectangles;return answer;
    }
    Array local_neighbors(Vector2 p) {
        const Vector2i key = bucket(p);
        if (neighbors.has(key)) return neighbors[key];
        Array local;
        for (int z = -1; z <= 1; ++z) for (int x = -1; x <= 1; ++x) local.append_array(at(spatial, key + Vector2i(x, z)));
        neighbors[key] = local;
        return local;
    }
    double walking_scale(Vector2 p, double radius) const {
        if (radius > .5) return 1.0;
        const Array local = at(buildings, bucket(p));
        for (int64_t i = 0; i < local.size(); ++i) {
            const Dictionary e = local[i], spec = specs[e[k.spec]];
            if (String(spec.get(k.role, String())) == k.barricade && circle_rect(p, radius, e[k.pos], Vector2(.5, .5))) return .35;
        }
        return 1.0;
    }
    void configure(const Dictionary &data) {
        Dictionary map = data["map"]; size = map["size"]; terrain = map["terrain"]; heights = map["heights"];
        flat = data["flat"]; bridges = data["bridges"]; mines = data["mines"];
        ruins = data["ruins"]; buildings = data["buildings"]; mine_buckets = data["mine_buckets"];
        spatial = data["spatial"]; neighbors = data["neighbors"]; specs = data["specs"];
    }
    bool building_clear(Vector2 p, double radius, int64_t ignore) const {
        Vector2i key = bucket(p);
        Array local = at(ruins, key);
        for (int64_t i = 0; i < local.size(); ++i) {
            Dictionary ruin = local[i];
            if (double(ruin[k.hp]) > 0 && circle_rect(p, radius + .02, ruin[k.pos], ruin[k.half])) return false;
        }
        Array local_mines = mines.size() <= 8 || radius + .02 > 2.0 ? mines : at(mine_buckets, key);
        for (int64_t i = 0; i < local_mines.size(); ++i) {
            Dictionary mine = local_mines[i];
            if (circle_rect(p, radius + .02, mine[k.pos], Vector2(.55, .55))) return false;
        }
        local = at(buildings, key);
        for (int64_t i = 0; i < local.size(); ++i) {
            Dictionary e = local[i];
            if (int64_t(e[k.id]) == ignore || double(e[k.hp]) <= 0) continue;
            Dictionary spec = specs[e[k.spec]];
            if (radius <= .5 && String(spec.get(k.role, String())) == k.barricade) continue;
            double half = double(spec[k.size]) * .5;
            if (circle_rect(p, radius + .02, e[k.pos], Vector2(half, half))) return false;
        }
        return true;
    }
    bool standing(Vector2 p, double radius, int64_t ignore, bool dynamic) {
        if (!land(p)) return false;
        if (!fast_flat(p, radius)) {
            const double level = height(p);
            const Vector2 directions[] = {Vector2(1, 0), Vector2(-1, 0), Vector2(0, -1), Vector2(0, 1), Vector2(.707, .707), Vector2(-.707, .707), Vector2(.707, -.707), Vector2(-.707, -.707)};
            for (Vector2 direction : directions) {
                Vector2 edge = p + direction * radius;
                if (!land(edge) || std::abs(height(edge) - level) > .8) return false;
            }
        }
        if (!building_clear(p, radius, ignore)) return false;
        if (!dynamic) return true;
        Vector2i key = bucket(p);
        Array local;
        if (neighbors.has(key)) local = neighbors[key];
        else {
            for (int z = -1; z <= 1; ++z) for (int x = -1; x <= 1; ++x) local.append_array(at(spatial, key + Vector2i(x, z)));
            neighbors[key] = local;
        }
        for (int64_t i = 0; i < local.size(); ++i) {
            Dictionary e = local[i];
            if (int64_t(e[k.id]) == ignore || double(e[k.hp]) <= 0) continue;
            double combined = radius + double(e[k.radius]) + .02;
            if (double(Vector2(e[k.pos]).distance_squared_to(p)) < combined * combined) return false;
        }
        return true;
    }
    Vector2 near_stand(Vector2 p, double radius, int64_t ignore, double maximum, bool dynamic) {
        if (standing(p, radius, ignore, dynamic)) return p;
        const int64_t rings = std::ceil(maximum / .6);
        for (int64_t ring = 1; ring <= rings; ++ring) {
            const double distance = ring * .6;
            for (int n = 0; n < 16; ++n) {
                const Vector2 point = p + Vector2::from_angle(double(n) * Math_TAU / 16.) * distance;
                if (standing(point, radius, ignore, dynamic)) return point;
            }
        }
        return Vector2(INFINITY, INFINITY);
    }
    bool segment_static(Vector2 start, Vector2 end, double radius, int64_t ignore) {
        if(!measurement_enabled)return segment_obstacles_clear(start,end,radius,ignore) && segment_static_sampled(start,end,radius,ignore);
        const auto started=std::chrono::steady_clock::now();
        const bool answer=segment_obstacles_clear(start,end,radius,ignore) && segment_static_sampled(start,end,radius,ignore);
        ++measured_queries;measured_ns+=std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now()-started).count();
        return answer;
    }
    bool segment_static_sampled(Vector2 start, Vector2 end, double radius, int64_t ignore) {
        const int checks = std::max(1, int(std::ceil(double(start.distance_to(end)) / .4)));
        if (fast_flat(start, radius)) {
            bool all_flat = true;
            for (int n = 1; n <= checks; ++n) {
                Vector2 point = start.lerp(end, double(n) / checks);
                if (!fast_flat(point, radius)) { all_flat = false; break; }
                if (!building_clear(point, radius, ignore)) return false;
            }
            if (all_flat) return true;
        }
        const int terrain_checks = std::max(1, int(std::ceil(double(start.distance_to(end)) / .25)));
        Vector2 previous = start;
        for (int n = 1; n <= terrain_checks; ++n) {
            Vector2 point = start.lerp(end, double(n) / terrain_checks);
            if (!land(point) || std::abs(height(point) - height(previous)) > .8) return false;
            previous = point;
        }
        for (int n = 1; n <= checks; ++n) if (!standing(start.lerp(end, double(n) / checks), radius, ignore, false)) return false;
        return true;
    }
};

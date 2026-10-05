// Cosmetic fog sampling only. TeamVision still owns observer construction and
// gameplay visibility. Mirror its numeric LOS exactly over the same 2 m cells.
class SightMaskSampler {
    static constexpr int cell_size = 2, bucket_size = 16;
    struct Cell {
        double height = 0.0;
        int64_t terrain = 0;
        uint64_t generation = 0;
    };
    struct Observer {
        Vector2 pos;
        double radius_sq = 0.0, eye_height = 0.0;
        bool air = false;
    };
    int64_t size = 0;
    uint64_t generation = 0;
    std::vector<Cell> cells;
    std::vector<Array> terrain_rows, height_rows;
    std::vector<Observer> local;
    const Variant pos_key{StringName{"pos"}}, radius_key{StringName{"radius_sq"}},
        air_key{StringName{"air"}}, eye_key{StringName{"eye_height"}};

    Cell &cell(int64_t x, int64_t z) {
        Cell &result = cells[z * size + x];
        if (result.generation != generation) {
            result.height = double(height_rows[z][x]);
            result.terrain = int64_t(terrain_rows[z][x]);
            result.generation = generation;
        }
        return result;
    }
    Vector2i coordinates(Vector2 p) const {
        return Vector2i(std::clamp<int64_t>(std::floor(p.x), 0, size - 1),
            std::clamp<int64_t>(std::floor(p.y), 0, size - 1));
    }
    int64_t terrain(Vector2 p) {
        const Vector2i c = coordinates(p);
        return cell(c.x, c.y).terrain;
    }
    double height(Vector2 p) {
        const Vector2i c = coordinates(p);
        const Cell &current = cell(c.x, c.y);
        const double level = current.height;
        if (current.terrain == 2) {
            const double fraction = double(p.y) - (c.y + 0.5);
            const int64_t next_z = c.y + (fraction >= 0.0 ? 1 : -1);
            if (next_z >= 0 && next_z < size) {
                const double next_height = cell(c.x, next_z).height;
                if (std::abs(next_height - level) <= 0.75)
                    return level + (next_height - level) * std::abs(fraction);
            }
        }
        return level;
    }
    bool terrain_line(const Observer &observer, Vector2 target, bool naval) {
        const double length = observer.pos.distance_to(target);
        const int steps = std::max(1, int(std::ceil(length / 1.5)));
        const double end_height = (naval ? height(target) - 2.65 : height(target)) + (naval ? 2.5 : 1.0);
        for (int index = 1; index < steps; ++index) {
            const double t = double(index) / double(steps);
            const Vector2 point = observer.pos.lerp(target, t);
            const double terrain_height = terrain(point) == 1 ? height(point) - 2.65 : height(point);
            if (terrain_height > observer.eye_height + (end_height - observer.eye_height) * t + 0.2) return false;
        }
        return true;
    }
    bool visible(Vector2 target, bool naval) {
        for (const Observer &observer : local) {
            if (double(observer.pos.distance_squared_to(target)) > observer.radius_sq) continue;
            if (observer.air || terrain_line(observer, target, naval)) return true;
        }
        return false;
    }

public:
    Dictionary refresh(const Dictionary &map, const Dictionary &observers,
            const Dictionary &changed_buckets, const PackedByteArray &previous) {
        Dictionary answer;
        answer["pixels"] = previous;
        answer["changed"] = false;
        answer["queries"] = int64_t(0);
        if (changed_buckets.is_empty()) return answer;
        size = int64_t(map["size"]);
        const int64_t width = (size + cell_size - 1) / cell_size;
        if (size <= 0 || previous.size() != width * width * 2) return answer;
        const Array terrain_data = map["terrain"], height_data = map["heights"];
        terrain_rows.resize(size); height_rows.resize(size);
        for (int64_t z = 0; z < size; ++z) {
            terrain_rows[z] = Array(terrain_data[z]);
            height_rows[z] = Array(height_data[z]);
        }
        cells.resize(size * size);
        // Cache numeric terrain only within this refresh. Live Array edits and
        // a different map of the same size are always read on the next call.
        if (++generation == 0) {
            for (Cell &current : cells) current.generation = 0;
            generation = 1;
        }
        PackedByteArray pixels = previous;
        uint8_t *output = pixels.ptrw();
        const Array keys = changed_buckets.keys();
        bool changed = false;
        int64_t queries = 0;
        constexpr int cells_per_bucket = bucket_size / cell_size;
        for (int64_t n = 0; n < keys.size(); ++n) {
            const Vector2i key = keys[n];
            const bool has_observers = observers.has(key);
            local.clear();
            if (has_observers) {
                const Array bucket = observers[key];
                local.reserve(bucket.size());
                for (int64_t index = 0; index < bucket.size(); ++index) {
                    const Dictionary record = bucket[index];
                    local.push_back({Vector2(record[pos_key]), double(record[radius_key]),
                        double(record[eye_key]), bool(record[air_key])});
                }
            }
            for (int64_t z = std::max<int64_t>(0, key.y * cells_per_bucket);
                    z < std::min<int64_t>(width, (int64_t(key.y) + 1) * cells_per_bucket); ++z) {
                for (int64_t x = std::max<int64_t>(0, key.x * cells_per_bucket);
                        x < std::min<int64_t>(width, (int64_t(key.x) + 1) * cells_per_bucket); ++x) {
                    const int64_t offset = (z * width + x) * 2;
                    bool current = false;
                    if (has_observers) {
                        const Vector2 point(std::min((x + 0.5) * cell_size, size - 0.001),
                            std::min((z + 0.5) * cell_size, size - 0.001));
                        current = visible(point, terrain(point) == 1);
                        ++queries;
                    }
                    const uint8_t value = current ? 255 : 0;
                    if (output[offset] != value) { output[offset] = value; changed = true; }
                    if (current && output[offset + 1] == 0) { output[offset + 1] = 255; changed = true; }
                }
            }
        }
        // Release map row references; only primitive values survive this call.
        terrain_rows.clear(); height_rows.clear();
        answer["pixels"] = pixels;
        answer["changed"] = changed;
        answer["queries"] = queries;
        return answer;
    }
};

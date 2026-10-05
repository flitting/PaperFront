#include <unordered_map>
// Renderer-side ownership cache. It retains the same model Dictionaries as the
// public world map, never simulation state, and is reset on setup/path switches.
// The ordered vector keeps the existing corpse/pool retirement order.
struct WorldModelCache {
    struct Entry {
        int64_t id=-1, team=-1;
        bool scaffold=false, native_pose=false;
        uint64_t seen=0;
        Dictionary model;
        PaperFrontRenderRecord *record=nullptr;
    };
    std::vector<Entry> ordered;
    std::unordered_map<int64_t,size_t> by_id;
    uint64_t frame=0;
    size_t holes=0;
    void clear() { by_id.clear(); ordered.clear(); holes=0; frame=0; }
    Entry &get(int64_t id) {
        auto found=by_id.find(id);
        if (found!=by_id.end()) return ordered[found->second];
        const size_t index=ordered.size();
        ordered.emplace_back(); ordered.back().id=id;
        by_id.emplace(id,index);
        return ordered.back();
    }
    void retire(Entry &entry) {
        by_id.erase(entry.id); entry.id=-1; entry.model=Dictionary(); entry.record=nullptr; ++holes;
    }
    void compact() {
        if (holes<256 || holes<by_id.size()) return;
        size_t next=0;
        for (size_t index=0;index<ordered.size();++index) {
            if (ordered[index].id<0) continue;
            if (next!=index) ordered[next]=std::move(ordered[index]);
            by_id[ordered[next].id]=next; ++next;
        }
        ordered.resize(next); holes=0;
    }
};

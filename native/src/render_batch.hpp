#include <godot_cpp/classes/multi_mesh.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/vector3i.hpp>

// Ordered submissions and upload cache owned by one world batch. The queue
// never owns its containing Dictionary or scene node, avoiding reference cycles.
class PaperFrontRenderBatch : public RefCounted {
    GDCLASS(PaperFrontRenderBatch, RefCounted)
    Ref<MultiMesh> multi;
    Node3D *node=nullptr;
    bool colored=false;
    int64_t capacity=0, visible_count=-1;
    std::vector<Transform3D> current, uploaded;
    std::vector<Color> colors, uploaded_colors;
    PackedFloat32Array buffer;
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("initialize","multi","node","enabled"), &PaperFrontRenderBatch::initialize);
        ClassDB::bind_method(D_METHOD("prepare","enabled"), &PaperFrontRenderBatch::prepare);
        ClassDB::bind_method(D_METHOD("append","transform","color"), &PaperFrontRenderBatch::append);
        ClassDB::bind_method(D_METHOD("is_enabled"), &PaperFrontRenderBatch::is_enabled);
        ClassDB::bind_method(D_METHOD("get_count"), &PaperFrontRenderBatch::get_count);
        ClassDB::bind_method(D_METHOD("get_capacity"), &PaperFrontRenderBatch::get_capacity);
        ClassDB::bind_method(D_METHOD("snapshot_transforms"), &PaperFrontRenderBatch::snapshot_transforms);
        ClassDB::bind_method(D_METHOD("snapshot_colors"), &PaperFrontRenderBatch::snapshot_colors);
        ClassDB::bind_method(D_METHOD("flush","bulk"), &PaperFrontRenderBatch::flush);
    }
public:
    bool enabled=false;
    void initialize(const Ref<MultiMesh> &p_multi, Node3D *p_node, bool p_enabled) {
        multi=p_multi; node=p_node; colored=multi->is_using_colors(); enabled=p_enabled;
    }
    bool prepare(bool p_enabled) {
        const bool changed=enabled!=p_enabled;
        enabled=p_enabled;
        current.clear(); colors.clear();
        if (changed) { uploaded.clear(); uploaded_colors.clear(); visible_count=-1; buffer=PackedFloat32Array(); }
        return changed;
    }
    bool is_enabled() const { return enabled; }
    int64_t get_count() const { return current.size(); }
    int64_t get_capacity() const { return capacity; }
    void append_transform(const Transform3D &transform) {
        current.push_back(transform);
        if (colored) colors.emplace_back(1,1,1,1);
    }
    void append(const Transform3D &transform, const Variant &color) {
        current.push_back(transform);
        if (colored) colors.push_back(color.get_type()==Variant::COLOR ? Color(color) : Color(1,1,1,1));
    }
    Array snapshot_transforms() const {
        Array result; result.resize(current.size());
        for (size_t i=0;i<current.size();++i) result[i]=current[i];
        return result;
    }
    Array snapshot_colors() const {
        Array result; result.resize(colors.size());
        for (size_t i=0;i<colors.size();++i) result[i]=colors[i];
        return result;
    }
    Vector3i flush(bool bulk) {
        const int64_t count=current.size(), stride=colored ? 16 : 12;
        capacity=multi->get_instance_count();
        if (count>capacity) {
            capacity=8; while (capacity<count) capacity*=2;
            multi->set_instance_count(capacity);
            // Establish Godot's CPU-side cache while the new GPU buffer is
            // still empty. Otherwise a later sparse update after set_buffer()
            // can synchronously read the GPU buffer back in _make_local().
            multi->set_instance_transform(0,current[0]);
            uploaded.clear(); uploaded_colors.clear(); buffer=PackedFloat32Array();
        }
        if (visible_count!=count) { multi->set_visible_instance_count(count); node->set_visible(count>0); visible_count=count; }
        if (!count) return Vector3i();
        if (buffer.size()!=capacity*stride) { buffer.resize(capacity*stride); buffer.fill(0); }
        float *data=nullptr;
        int64_t changed_transforms=0, changed_colors=0;
        const bool whole_buffer=bulk && count>=8;
        for (int64_t i=0;i<count;++i) {
            const Transform3D &t=current[i];
            const bool changed=size_t(i)>=uploaded.size() || uploaded[i]!=t;
            if (changed) {
                if (!data) data=buffer.ptrw();
                float *out=data+i*stride;
                for (int row=0;row<3;++row) {
                    for (int col=0;col<3;++col) out[row*4+col]=t.basis[row][col];
                    out[row*4+3]=t.origin[row];
                }
                if (size_t(i)>=uploaded.size()) uploaded.push_back(t); else uploaded[i]=t;
                ++changed_transforms;
                if (!whole_buffer) multi->set_instance_transform(i,t);
            }
            if (colored) {
                const Color &color=colors[i];
                if (size_t(i)>=uploaded_colors.size() || uploaded_colors[i]!=color) {
                    if (!data) data=buffer.ptrw();
                    float *out=data+i*stride+12;
                    out[0]=color.r; out[1]=color.g; out[2]=color.b; out[3]=color.a;
                    if (size_t(i)>=uploaded_colors.size()) uploaded_colors.push_back(color); else uploaded_colors[i]=color;
                    ++changed_colors;
                    if (!whole_buffer) multi->set_instance_color(i,color);
                }
            }
        }
        if (whole_buffer && (changed_transforms || changed_colors)) multi->set_buffer(buffer);
        return Vector3i(changed_transforms,changed_colors,1);
    }
};
struct BatchKeys {
    const Variant queue{StringName("native_queue")}, transforms{StringName("transforms")}, colors{StringName("colors")},
        uploaded{StringName("uploaded")}, uploaded_colors{StringName("uploaded_colors")}, visible{StringName("visible_count")}, capacity{StringName("capacity")};
};
static PaperFrontRenderBatch *render_batch(const Dictionary &batch) {
    static const Variant key{StringName("native_queue")};
    Object *object=batch.get(key,Variant());
    return Object::cast_to<PaperFrontRenderBatch>(object);
}
// The renderer creates batches once; retain their descriptors and native
// queues instead of resolving every Dictionary field again on every frame.
// No queue has a back-reference to this registry.
struct RenderBatchRegistry {
    struct Entry {
        Dictionary batch;
        Ref<PaperFrontRenderBatch> queue;
        int64_t visible=-1, capacity=-1;
    };
    std::vector<Entry> entries;
    void clear() { entries.clear(); }
    void add(const Dictionary &batch) {
        auto *queue=render_batch(batch);
        if (!queue) return;
        entries.push_back({batch,Ref<PaperFrontRenderBatch>(queue),-1,-1});
    }
    void begin(const BatchKeys &k) {
        for (auto &entry:entries) {
            if (!entry.queue->prepare(true)) continue;
            Array(entry.batch[k.transforms]).clear(); Array(entry.batch[k.colors]).clear();
            Array(entry.batch[k.uploaded]).clear(); Array(entry.batch[k.uploaded_colors]).clear();
            entry.batch[k.visible]=-1; entry.visible=-1; entry.capacity=-1;
        }
    }
    Vector3i flush(const BatchKeys &k,bool bulk) {
        Vector3i totals;
        for (auto &entry:entries) {
            totals+=entry.queue->flush(bulk);
            const int64_t visible=entry.queue->get_count(), capacity=entry.queue->get_capacity();
            if (entry.visible!=visible) { entry.batch[k.visible]=visible; entry.visible=visible; }
            if (entry.capacity!=capacity) { entry.batch[k.capacity]=capacity; entry.capacity=capacity; }
        }
        return totals;
    }
};

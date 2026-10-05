PackedByteArray build_flat_terrain_mask_native(const Dictionary &map) {
    const int64_t size=map["size"];
    const Array rows=map["terrain"], levels=map["heights"];
    std::vector<int64_t> terrain(size*size);
    std::vector<double> heights(size*size);
    for (int64_t z=0;z<size;++z) {
        const Array row=rows[z], height_row=levels[z];
        for (int64_t x=0;x<size;++x) { terrain[z*size+x]=int64_t(row[x]); heights[z*size+x]=double(height_row[x]); }
    }
    PackedByteArray result; result.resize(size*size); result.fill(0);
    uint8_t *mask=result.ptrw();
    for (int64_t z=1;z<size-1;++z) for (int64_t x=1;x<size-1;++x) {
        bool good=true;
        const double height=heights[z*size+x];
        for (int dz=-1;dz<=1 && good;++dz) for (int dx=-1;dx<=1;++dx) {
            const int64_t index=(z+dz)*size+x+dx;
            if ((terrain[index]!=0 && terrain[index]!=3) || std::abs(heights[index]-height)>.01) { good=false; break; }
        }
        if (good) mask[z*size+x]=1;
    }
    return result;
}

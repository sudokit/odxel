// uniform data
struct DispatchParams {
    float4x4 inv_proj_mat;
    float3 camera_origin;
};
[[vk::binding(0, 2)]]
ConstantBuffer<DispatchParams> pc;

// // storage buffers
// [[vk::binding(0, 1)]]
// StructuredBuffer<Node> node_pool; // storage buffer

// [[vk::binding(1, 1)]]
// StructuredBuffer<uint8_t> leaf_data; // storage buffer

// storage rw texture
[[vk::binding(0, 1)]]
RWTexture2D<float4> output_albedo_tex; // storage texture

[numthreads(8, 8)]
void ComputeMain(uint2 pos: SV_DispatchThreadID) {
  int w, h;
  output_albedo_tex.GetDimensions(w, h);
  if (any(pos > float2(w, h))) return;

  output_albedo_tex[pos] = mul(float4(pc.camera_origin, 1.0), pc.inv_proj_mat);
}

struct Node {
    uint packed_data[3];

    property bool IsLeaf {
        get { return (packed_data[0] & 1) != 0; }
    }
    property uint ChildPtr {
        get { return packed_data[0] >> 1; }
    }
    property uint64_t ChildMask {
        get { return packed_data[1] | uint64_t(packed_data[2]) << 32; }
    }
}


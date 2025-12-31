// uniform data
struct DispatchParams {
  float4x4 inv_proj_mat;
  float4 camera_origin;
  int4 world_origin;
  uint tree_scale;
};
[[vk::binding(0, 2)]]
ConstantBuffer<DispatchParams> pc;

// // storage buffers
[[vk::binding(0, 0)]]
StructuredBuffer<Node> node_pool; // storage buffer

// [[vk::binding(1, 1)]]
// StructuredBuffer<uint8_t> leaf_data; // storage buffer

// storage rw texture
[[vk::binding(0, 1), vk::image_format("rgba8")]]
RWTexture2D<float4> output_albedo_tex; // storage texture

static const float3 LIGHT_DIR = normalize(float3(1, 1, 1));
static const float3 LIGHT_COLOR = float3(1, 1, 1);

[numthreads(8, 8)]
void ComputeMain(uint2 pos: SV_DispatchThreadID) {
  int w, h;
  output_albedo_tex.GetDimensions(w, h);
  if (any(pos > float2(w, h)))
    return;

  float3 ray_pos, ray_dir;
  get_ray(pos, ray_pos, ray_dir);

  Hit_Info ht = ray_cast(pc.world_origin.xyz, ray_pos, ray_dir, false);
  float3 albedo;

  if (!ht.miss) {
    // float normal_iters = ht.iters / 256;
    // albedo = heatmap(normal_iters);
    albedo = ht.normal;
    float diff = max(dot(ht.normal, -LIGHT_DIR), 0.0);
    albedo = diff * LIGHT_COLOR * float3(0, 0.2, 0.4) * 5;
  } else {
    albedo = 0.5;
  }

  output_albedo_tex[pos] = float4(albedo, 1.0);
}

Hit_Info ray_cast(int3 world_origin, float3 ray_pos, float3 ray_dir,
                  bool coarse) {
  float scale = 1.0 / (1 << pc.tree_scale);
  float3 origin = world_origin * scale + ray_pos * scale + 1.0;

  Hit_Info ht = traverse(origin, ray_dir, coarse);

  if (ht.material_id != 0) {
    ht.pos = (ht.pos - 1.0 - world_origin * scale) * (1 << pc.tree_scale);
  }

  return ht;
}

Hit_Info traverse(float3 origin, float3 dir, bool coarse) {
  uint groupId = spirv_asm {
            OpCapability VariablePointers;
            result:$$uint = OpLoad builtin(LocalInvocationIndex:uint);
        };
  static groupshared uint gs_stack[64][11];
  // uint stack[11];
  uint *stack = &gs_stack[groupId][0];
  int scale_exp = 21; // 0.25

  uint node_idx = 0; // root
  Node node = node_pool[node_idx];

  float3 inv_dir = 1.0f / -abs(dir);
  uint mirror_mask = 0;

  // Mirror coordinates to negative ray octant
  if (dir.x > 0)
    mirror_mask |= 3 << 0;
  if (dir.y > 0)
    mirror_mask |= 3 << 4;
  if (dir.z > 0)
    mirror_mask |= 3 << 2;

  origin = get_mirrored_pos(origin, dir, true);
  float3 pos = clamp(origin, 1.0f, 1.9999999f);

  float3 side_dist;
  int child_idx;
  int i;
  bool skip_next_hit =
      true; // true on first iteration so that self-intersections are ignored

  // Clip rays starting outside tree
  if (any(pos != origin)) {
    float3 t0 = (float3(2.0f) - origin) * inv_dir;
    float3 t1 = (float3(1.0f) - origin) * inv_dir;
    float tmin = max(max(t0.x, t0.y), max(t0.z, 0.0f));
    float tmax = min(min(t1.x, t1.y), t1.z);

    pos = clamp(origin - abs(dir) * tmin, 1.0f, 1.9999999f);
    side_dist = -t0; // negation corrects for normal calculation

    // The first hit may be valid if we start outside the tree and
    // there are voxels at the edges.
    // By coincidence, setting this flag to false works to reject rays
    // that do not intersect the tree without extra code.
    skip_next_hit = tmin >= tmax;
  }

  for (i = 0; i < 256; i++) {
    if (coarse && i > 256/8 && node.is_leaf)
      break;

    child_idx = get_node_cell_index(pos, scale_exp) ^ mirror_mask;

    // Descend
    while (bit_test_half64(node.child_mask, child_idx, 1) && !node.is_leaf) {
      stack[scale_exp >> 1] = node_idx;
      node_idx = node.child_idx + prefix_popcnt64(node.child_mask, child_idx);
      node = node_pool[node_idx];

      scale_exp -= 2;
      child_idx = get_node_cell_index(pos, scale_exp) ^ mirror_mask;
    }
    if (bit_test_half64(node.child_mask, child_idx, 1) && node.is_leaf &&
        !skip_next_hit)
      break;

    int adv_scale_exp = scale_exp;

    if (!bit_test_half64(node.child_mask, child_idx & 0b101010, 0x00330033))
      adv_scale_exp++;

    // Compute next pos by intersecting with max cube edges
    float3 edgePos = floor_scale(pos, adv_scale_exp);

    side_dist = (edgePos - origin) * inv_dir;
    float tmax = min(min(side_dist.x, side_dist.y), side_dist.z);

    int3 maxSiblBounds =
        bit_cast<int3>(edgePos) +
        select(side_dist == tmax, -1, (1 << adv_scale_exp) - 1);
    pos = min(origin - abs(dir) * tmax, asfloat(maxSiblBounds));

    // Find carry bit to tell which node we should ascend to
    uint3 diffPos = asuint(pos) ^ asuint(edgePos);
    int diffExp = firstbithigh((diffPos.x | diffPos.y | diffPos.z) &
                               0xFFAAAAAA); // 31 - lzcnt

    if (diffExp > scale_exp) {
      scale_exp = diffExp;
      if (diffExp > 21)
        break; // going out of root?

      node_idx = stack[scale_exp >> 1];
      node = node_pool[node_idx];
    }
    skip_next_hit = false;
  }

  Hit_Info hit;
  hit.material_id = 0;

  if (node.is_leaf && scale_exp <= 21) {
    pos = get_mirrored_pos(pos, dir, false);

    hit.material_id = 1;
    hit.pos = pos;

    float tmax = min(min(side_dist.x, side_dist.y), side_dist.z);
    bool3 sideMask = tmax >= side_dist;
    hit.normal = select(sideMask, -sign(dir), 0.0);
    hit.iters = i;
  }
  return hit;
}

void get_ray(int2 screenPos, out float3 rayPos, out float3 rayDir) {
  int x, y;
  output_albedo_tex.GetDimensions(x, y);
  float2 uv = (screenPos + 0.5) / float2(x, y);
  uv = uv * 2 - 1;
  float4 far = mul(pc.inv_proj_mat, float4(uv, 1, 1));
  rayDir = normalize(far.xyz / far.w);
  rayPos = pc.camera_origin.xyz;
}

struct Hit_Info {
  float3 pos;
  float3 normal;
  uint material_id;
  uint iters;

  property bool miss {
    get { return material_id == 0; }
  }
}

struct Node {
  uint packed_data[3];

  property bool is_leaf {
    get { return (packed_data[0] & 1) != 0; }
  }
  property uint child_idx {
    get { return packed_data[0] >> 1; }
  }
  property uint64_t child_mask {
    get { return packed_data[1] | uint64_t(packed_data[2]) << 32; }
  }
}

// utils
static float3 get_mirrored_pos(float3 pos, float3 dir, bool rangeCheck) {
  float3 mirrored = asfloat(asuint(pos) ^ 0x7FFFFF);
  // XOR'ing will only work if the coords are in range [1.0, 2.0),
  // so just fallback to the original subtraction if that's not the case.
  if (rangeCheck && any(pos < 1.0 || pos >= 2.0))
    mirrored = 3.0 - pos;
  return select(dir > 0, mirrored, pos);
}

static int get_node_cell_index(float3 pos, int scale_exp) {
  uint3 cellPos = asuint(pos) >> scale_exp & 3;
  return cellPos.x + cellPos.z * 4 + cellPos.y * 16;
}

// floor(pos / scale) * scale
static float3 floor_scale(float3 pos, int scale_exp) {
  uint mask = ~0u << scale_exp;
  return asfloat(asuint(pos) & mask);
}

// Count number of set bits in variable range [0..width]
public uint prefix_popcnt64(uint64_t mask, uint width) {
  // return popcnt64(mask & ((1ull << mask) - 1));
  uint himask = uint(mask);
  uint count = 0;

  if (width >= 32) {
    count = countbits(himask);
    himask = uint(mask >> 32);
  }
  uint m = 1u << (width & 31u);
  count += countbits(himask & (m - 1u));

  return count;
}

public uint popcnt64(uint64_t mask) {
  uint a = countbits(uint(mask >> 0));
  uint b = countbits(uint(mask >> 32));
  return a + b;
}

public uint tzcnt64(uint64_t mask) {
  uint a = uint(mask >> 0);
  uint b = uint(mask >> 32);
  uint c = firstbitlow(a != 0 ? a : b);
  return a != 0 ? c : c + 32;
}

// Cheaper approximation of `(value >> shift & mask) != 0` that gives
// correct results for single bits and tile octant tests.
// Some GPUs don't support native 64-bit shifts and correct emulation
// is noticeably slow (this improves traversal by as much as 20% on Intel Xe1).
public bool bit_test_half64(uint64_t value, uint shift, uint mask) {
  // return (value >> shift & mask) != 0;
  uint low = shift < 32 ? uint(value) : uint(value >> 32);
  return (low >> (shift & 31) & mask) != 0;
}

float3 heatmap(float t) {
  float3 color =
      clamp(float3(1.5 - abs(4.0 * t - 3.0), 1.5 - abs(4.0 * t - 2.0),
                   1.5 - abs(4.0 * t - 1.0)),
            0.0, 1.0);
  return color;
}


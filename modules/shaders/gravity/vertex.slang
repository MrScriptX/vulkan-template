struct VSOutput
{
    float4 sv_position : SV_Position;
    float2 ndc : NDC;
};

struct Object
{
    float2 pos;
    float mass;
}

StructuredBuffer<Object> objects;

struct PushConstant
{
    float2 world_size;
    float2 camera_pos;
}

[push_constant]
PushConstant pc;

static const float scale = 10.0;

[shader("vertex")]
VSOutput main(uint vertexId: SV_VertexID, uint instanceId: SV_InstanceID)
{
    // Two triangles forming a quad.
    static const float2 vertices[6] =
        {
            float2(-1.0, -1.0),
            float2(1.0, -1.0),
            float2(-1.0, 1.0),

            float2(-1.0, 1.0),
            float2(1.0, -1.0),
            float2(1.0, 1.0)
        };

    float2 local = vertices[vertexId];

    Object object = objects[instanceId];

    // World-space position relative to camera.
    float2 camera_space = object.pos - pc.camera_pos;

    // World → NDC.
    float2 ndc = camera_space / (pc.world_size * 0.5);

    // Mass determines the radius.
    float radius = object.mass * scale;

    // Convert from pixel-like radius to NDC.
    float2 radius_ndc = radius / (pc.world_size * 0.5);
    ndc += local * radius_ndc;

    VSOutput output;

    output.sv_position = float4(ndc, 0.0, 1.0);

    // Convert [-1,1] quad coordinates to [0,1].
    output.ndc = local * 0.5 + 0.5;

    return output;
}

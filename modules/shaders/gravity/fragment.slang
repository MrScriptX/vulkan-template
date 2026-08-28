struct Object
{
    float2 pos;
}

StructuredBuffer<Object> object;

struct PSInput
{
    float4 sv_position : SV_Position;
    float2 ndc : NDC;
};

static const float radius = 0.05;
static const float edge_softness = 0.005;

[shader("fragment")]
float4 main(PSInput input) : SV_Target
{
    float2 center = object[0].pos;
    float dist = length(input.ndc - center);

    float alpha = 1.0 - smoothstep(radius - edge_softness, radius, dist);
    if (alpha <= 0.0)
    {
        discard;
    }

    return float4(1.0, 1.0, 1.0, alpha);
}

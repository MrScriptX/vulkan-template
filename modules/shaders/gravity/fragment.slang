struct Object
{
    float2 pos;
    float mass;
}

struct PSInput
{
    float4 sv_position : SV_Position;
    float2 ndc : NDC;
};

static const float scale = 100.0;
static const float edge_softness = 0.005;

[shader("fragment")]
float4 main(PSInput input) : SV_Target
{
    // Center of the circle.
    float2 p = input.ndc - float2(0.5, 0.5);

    // Outside the unit circle -> discard.
    if (dot(p, p) > 0.25)
        discard;

    return float4(1.0, 1.0, 1.0, 1.0);
}

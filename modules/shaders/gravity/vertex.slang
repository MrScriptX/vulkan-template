struct VSOutput
{
    float4 sv_position : SV_Position;
    float2 ndc : NDC;
};

[shader("vertex")]
VSOutput main(uint vertexId: SV_VertexID)
{
    VSOutput output;

    float2 pos = float2((vertexId << 1) & 2, vertexId & 2);
    float2 ndc = pos * 2.0 - 1.0;

    output.sv_position = float4(ndc, 0.0, 1.0);
    output.ndc = ndc;

    return output;
}

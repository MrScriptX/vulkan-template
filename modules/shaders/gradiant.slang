RWTexture2D image;

[shader("compute")]
[numthreads(16, 16, 1)]
void main(uint3 threadId: SV_DispatchThreadID, uint3 localId: SV_GroupThreadID)
{
    int2 texel_coord = int2(threadId.xy);
    
    int2 size;
    image.GetDimensions(size.x, size.y);

    if (texel_coord.x < size.x && texel_coord.y < size.y)
    {
        float4 color = { 0, 0, 0, 1 };
        if (localId.x != 0 && localId.y != 0)
        {
            color.x = float(texel_coord.x) / float(size.x);
            color.y = float(texel_coord.y) / float(size.y);
        }

        image[texel_coord] = color;
    }
}
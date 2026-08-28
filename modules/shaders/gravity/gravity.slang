
struct Object
{
    float2 pos;
}

[push_constant]
int32_t delta_time;

RWStructuredBuffer<Object> object;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 threadId: SV_DispatchThreadID, uint3 localId: SV_GroupThreadID)
{
    float2 velocity = float2(0.01, 0);
    object[0].pos += velocity * (float32_t(delta_time) / 1000.0 / 60.0);
}
struct Object
{
    float2 pos;
    float mass;
}

[push_constant]
int32_t delta_time;

RWStructuredBuffer<Object> objects;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 threadId: SV_DispatchThreadID, uint3 localId: SV_GroupThreadID)
{
    uint object_id = threadId.x;

    float2 velocity = float2(1, 0);
    objects[object_id].pos += velocity * (float32_t(delta_time) / 1000.0 / 60.0);
}
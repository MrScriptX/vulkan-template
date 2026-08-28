struct Object
{
    float2 pos; // in km
    float mass; // in kg
}

[push_constant]
int32_t delta_time;

RWStructuredBuffer<Object> objects;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 threadId: SV_DispatchThreadID, uint3 localId: SV_GroupThreadID)
{
    uint object_id = threadId.x;
    float32_t dt = (float32_t(delta_time) / 1000.0 / 60.0);

    float2 velocity = float2(1, 0);
    objects[object_id].pos += velocity * dt;

    // TODO : compute F(dx/x) et F(dy/y) sachant que F = G * (Ma * Mb)/d²
    // x(t) = v0(dx/x) * t + x0
    // y(t) = v0(dy/y) * t + y0
}
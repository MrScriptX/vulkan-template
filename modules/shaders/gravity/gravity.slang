struct Object
{
    float2 pos; // in km
    float mass; // in kg
    float velocity; // in km/h
}

[push_constant]
int32_t delta_time;

RWStructuredBuffer<Object> objects;

static const float G = 0; // gravitational constant

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 threadId: SV_DispatchThreadID, uint3 localId: SV_GroupThreadID)
{
    uint object_id = threadId.x;
    float32_t dt = (float32_t(delta_time) / 1000.0 / 60.0);

    float2 velocity = float2(1, 0);
    objects[object_id].pos += velocity * dt;

    float2 p1 = float2(0); // new position
    for (uint i = 0; i < objects.getCount(); i++)
    {
        if (i == object_id) continue; // same object

        float A = objects[object_id].velocity * dt;

        float2 d;
        d.x = objects[i].pos.x - objects[object_id].pos.x;
        d.y = objects[i].pos.y - objects[object_id].pos.y;

        float2 a;
        a.x = acceleration(objects[i].mass, d.x);
        a.y = acceleration(objects[i].mass, d.y);

        float2 f;
        f.x = 0.5 * a.x * dt;
        f.y = 0.5 * a.y * dt;

        p1.x += A + f.x;
        p1.y += A + f.y;
    }

    objects[object_id].pos = p1; // new position
}

float acceleration(float mass, float distance)
{
    return G * (mass / pow(distance, 2));
}
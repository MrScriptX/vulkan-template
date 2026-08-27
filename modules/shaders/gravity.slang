
struct Object
{
    int32_t2 pos;
}

RWStructuredBuffer<Object> object;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 threadId: SV_DispatchThreadID, uint3 localId: SV_GroupThreadID)
{
    
}
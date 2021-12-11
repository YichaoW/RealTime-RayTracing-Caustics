// Modified from Raytracing.hlsl

#ifndef PHOTONTRACING_HLSL
#define PHOTONTRACING_HLSL

#define HLSL
#include "RaytracingHlslCompat.h"
#include "ProceduralPrimitivesLibrary.hlsli"
#include "RaytracingShaderHelper.hlsli"

//***************************************************************************
//*****------ Shader resources bound via root signatures -------*************
//***************************************************************************

// Scene wide resources.
//  g_* - bound via a global root signature.
//  l_* - bound via a local root signature.
RaytracingAccelerationStructure g_scene : register(t0, space0);
RWTexture2D<float4> g_renderTarget : register(u0);
ConstantBuffer<SceneConstantBuffer> g_sceneCB : register(b0);

// Triangle resources
ByteAddressBuffer g_indices : register(t1, space0);
StructuredBuffer<Vertex> g_vertices : register(t2, space0);

// Procedural geometry resources
StructuredBuffer<PrimitiveInstancePerFrameBuffer> g_AABBPrimitiveAttributes : register(t3, space0);
ConstantBuffer<PrimitiveConstantBuffer> l_materialCB : register(b1);
ConstantBuffer<PrimitiveInstanceConstantBuffer> l_aabbCB: register(b2);

// Photon Resource
RWStructuredBuffer<Photon> g_photons: register(u1);


//***************************************************************************
//****************------ Utility functions -------***************************
//***************************************************************************

float rnd3( float2 uv, float2 k) { return cos( fmod( 123456789., 256. * dot(uv,k) ) ); }

void StorePhotonNaive(Photon p) {
    uint3 launchIndex = DispatchRaysIndex();
    uint3 launchDimension = DispatchRaysDimensions();
    int index = launchIndex.y * launchDimension.x + launchIndex.x;
    // Photon p;
    // p.throughput = rnd3(DispatchRaysIndex().xy, float2(23.1406926327792690, 2.6651441426902251));
    g_photons[index] = p;
}

void StorePhoton(Photon p) {
    int photonIndex = GetPhotonSpatialIndex(p.position);
    if (photonIndex == -1) {
        return;
    }
    Photon temp = g_photons[photonIndex];

    if (temp.count == 0) {
        p.count = 1;
        g_photons[photonIndex] = p;
    }
    else {
        float3 oldV;
        InterlockedAdd(g_photons[photonIndex].throughput.x, p.throughput.x, oldV.x);
        InterlockedAdd(g_photons[photonIndex].throughput.y, p.throughput.y, oldV.y);
        InterlockedAdd(g_photons[photonIndex].throughput.z, p.throughput.z, oldV.z);
        InterlockedAdd(g_photons[photonIndex].count, 1, oldV.z);

    }
}

// Diffuse lighting calculation.
float CalculateDiffuseCoefficient(in float3 hitPosition, in float3 incidentLightRay, in float3 normal)
{
    float fNDotL = saturate(dot(-incidentLightRay, normal));
    return fNDotL;
}

// Phong lighting specular component
float4 CalculateSpecularCoefficient(in float3 hitPosition, in float3 incidentLightRay, in float3 normal, in float specularPower)
{
    float3 reflectedLightRay = normalize(reflect(incidentLightRay, normal));
    return pow(saturate(dot(reflectedLightRay, normalize(-WorldRayDirection()))), specularPower);
}


// Phong lighting model = ambient + diffuse + specular components.
float4 CalculatePhongLighting(in float4 albedo, in float3 normal, in bool isInShadow, in float diffuseCoef = 1.0, in float specularCoef = 1.0, in float specularPower = 50)
{
    float3 hitPosition = HitWorldPosition();
    float3 lightPosition = g_sceneCB.lightPosition.xyz;
    float shadowFactor = isInShadow ? InShadowRadiance : 1.0;
    float3 incidentLightRay = normalize(hitPosition - lightPosition);

    // Diffuse component.
    float4 lightDiffuseColor = g_sceneCB.lightDiffuseColor;
    float Kd = CalculateDiffuseCoefficient(hitPosition, incidentLightRay, normal);
    float4 diffuseColor = shadowFactor * diffuseCoef * Kd * lightDiffuseColor * albedo;

    // Specular component.
    float4 specularColor = float4(0, 0, 0, 0);
    if (!isInShadow)
    {
        float4 lightSpecularColor = float4(1, 1, 1, 1);
        float4 Ks = CalculateSpecularCoefficient(hitPosition, incidentLightRay, normal, specularPower);
        specularColor = specularCoef * Ks * lightSpecularColor;
    }

    // Ambient component.
    // Fake AO: Darken faces with normal facing downwards/away from the sky a little bit.
    float4 ambientColor = g_sceneCB.lightAmbientColor;
    float4 ambientColorMin = g_sceneCB.lightAmbientColor - 0.1;
    float4 ambientColorMax = g_sceneCB.lightAmbientColor;
    float a = 1 - saturate(dot(normal, float3(0, -1, 0)));
    ambientColor = albedo * lerp(ambientColorMin, ambientColorMax, a);

    return ambientColor + diffuseColor + specularColor;
}

//***************************************************************************
//*****------ TraceRay wrappers for radiance and shadow rays. -------********
//***************************************************************************

// Trace a radiance ray into the scene and returns a shaded color.
float4 TraceRadianceRay(in Ray ray, in UINT currentRayRecursionDepth)
{
    if (currentRayRecursionDepth >= MAX_RAY_RECURSION_DEPTH)
    {
        return float4(0, 0, 0, 0);
    }

    // Set the ray's extents.
    RayDesc rayDesc;
    rayDesc.Origin = ray.origin;
    rayDesc.Direction = ray.direction;
    // Set TMin to a zero value to avoid aliasing artifacts along contact areas.
    // Note: make sure to enable face culling so as to avoid surface face fighting.
    rayDesc.TMin = 0;
    rayDesc.TMax = 10000;
    RayPayload rayPayload = { float4(0, 0, 0, 0), currentRayRecursionDepth + 1 };
    TraceRay(g_scene,
        RAY_FLAG_CULL_BACK_FACING_TRIANGLES,
        TraceRayParameters::InstanceMask,
        TraceRayParameters::HitGroup::Offset[RayType::Radiance],
        TraceRayParameters::HitGroup::GeometryStride,
        TraceRayParameters::MissShader::Offset[RayType::Radiance],
        rayDesc, rayPayload);

    return rayPayload.color;
}

// Trace a shadow ray and return true if it hits any geometry.
bool TraceShadowRayAndReportIfHit(in Ray ray, in UINT currentRayRecursionDepth)
{
    if (currentRayRecursionDepth >= MAX_RAY_RECURSION_DEPTH)
    {
        return false;
    }

    // Set the ray's extents.
    RayDesc rayDesc;
    rayDesc.Origin = ray.origin;
    rayDesc.Direction = ray.direction;
    // Set TMin to a zero value to avoid aliasing artifcats along contact areas.
    // Note: make sure to enable back-face culling so as to avoid surface face fighting.
    rayDesc.TMin = 0;
    rayDesc.TMax = 10000;

    // Initialize shadow ray payload.
    // Set the initial value to true since closest and any hit shaders are skipped. 
    // Shadow miss shader, if called, will set it to false.
    ShadowRayPayload shadowPayload = { true };
    TraceRay(g_scene,
        RAY_FLAG_CULL_BACK_FACING_TRIANGLES
        | RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH
        | RAY_FLAG_FORCE_OPAQUE             // ~skip any hit shaders
        | RAY_FLAG_SKIP_CLOSEST_HIT_SHADER, // ~skip closest hit shaders,
        TraceRayParameters::InstanceMask,
        TraceRayParameters::HitGroup::Offset[RayType::Shadow],
        TraceRayParameters::HitGroup::GeometryStride,
        TraceRayParameters::MissShader::Offset[RayType::Shadow],
        rayDesc, shadowPayload);

    return shadowPayload.hit;
}


void TracePhotonRay(in Ray ray, in PhotonRayPayload rayPayload, in UINT currentRayRecursionDepth, float3 throughput, bool prev_specular)
{
    if (currentRayRecursionDepth >= MAX_RAY_RECURSION_DEPTH)
    {
        return;
    }

    // Set the ray's extents.
    RayDesc rayDesc;
    rayDesc.Origin = ray.origin;
    rayDesc.Direction = ray.direction;
    // Set TMin to a zero value to avoid aliasing artifacts along contact areas.
    // Note: make sure to enable face culling so as to avoid surface face fighting.
    rayDesc.TMin = 0;
    rayDesc.TMax = 10000;
    // PhotonRayPayload rayPayload =
    // {
    //     ray.origin,         // hit position
    //     ray.direction,      // ray direction 
    //     prev_specular,      // previous hit is specular
    //     throughput,    // throughput
    //     currentRayRecursionDepth + 1,                  // recursion depth
    // };
    rayPayload.position = ray.origin;
    rayPayload.direction = ray.direction;
    rayPayload.throughput = throughput;
    rayPayload.prev_specular = prev_specular;
    rayPayload.recursionDepth = currentRayRecursionDepth + 1;

    TraceRay(g_scene,
        RAY_FLAG_CULL_BACK_FACING_TRIANGLES,
        TraceRayParameters::InstanceMask,
        TraceRayParameters::HitGroup::Offset[RayType::Radiance],
        TraceRayParameters::HitGroup::GeometryStride,
        TraceRayParameters::MissShader::Offset[RayType::Radiance],
        rayDesc, rayPayload);
}


//https://www.reedbeta.com/blog/quick-and-easy-gpu-random-numbers-in-d3d11/ random number in d3d11

static uint rng_state;
uint wang_hash(uint seed)
{
    seed = (seed ^ 61) ^ (seed >> 16);
    seed *= 9;
    seed = seed ^ (seed >> 4);
    seed *= 0x27d4eb2d;
    seed = seed ^ (seed >> 15);
    return seed;
}

float rand_xorshift()
{
    // Xorshift algorithm from George Marsaglia's paper
    rng_state ^= (rng_state << 13);
    rng_state ^= (rng_state >> 17);
    rng_state ^= (rng_state << 5);
    return rng_state * (1.0f / 4294967296.0f);
}

float3 calculateRandomDirectionInHemisphere(in float3 normal) {

    float up = sqrt(rand_xorshift()); // cos(theta)
    float over = sqrt(1 - up * up); // sin(theta)
    float around = rand_xorshift() * TWO_PI;

    // Find a direction that is not the normal based off of whether or not the
    // normal's components are all equal to sqrt(1/3) or whether or not at
    // least one component is less than sqrt(1/3). Learned this trick from
    // Peter Kutz.

    float3 directionNotNormal;
    if (abs(normal.x) < SQRT_OF_ONE_THIRD) {
        directionNotNormal = float3(1, 0, 0);
    }
    else if (abs(normal.y) < SQRT_OF_ONE_THIRD) {
        directionNotNormal = float3(0, 1, 0);
    }
    else {
        directionNotNormal = float3(0, 0, 1);
    }

    // Use not-normal direction to generate two perpendicular directions
    float3 perpendicularDirection1 =
        normalize(cross(normal, directionNotNormal));
    float3 perpendicularDirection2 =
        normalize(cross(normal, perpendicularDirection1));

    return up * normal
        + cos(around) * over * perpendicularDirection1
        + sin(around) * over * perpendicularDirection2;
}

float3 SquareToSphereUniform(float2 samplePoint)
{
    float radius = 1.f;

    float phi = samplePoint.y * PI;
    float theta = samplePoint.x * TWO_PI;

    float3 result;
    result.x = radius * cos(theta) * sin(phi);
    result.y = radius * cos(phi);
    result.z = radius * sin(theta) * sin(phi);
    return result;
}

float3 SamplePointLight(float2 lightUV)
{
   float2 signUV = float2(lightUV.x > 0 ? 1 : -1, lightUV.y > 0 ? 1 : -1);
   float2 absUV = abs(lightUV.xy);
   float3 direction = float3(lightUV.xy, absUV.x + absUV.y - 1);
   if (direction.z > 0)
   {
       direction.xy = (1 - absUV.yx) * signUV;
   }
   return normalize(direction);
}


//***************************************************************************
//********************------ Ray gen shader.. -------************************
//***************************************************************************

[shader("raygeneration")]
void MyRaygenShader_Photon()
{
    // Generate a ray for a camera pixel corresponding to an index from the dispatched 2D grid.
    //Ray ray = GenerateCameraRay(DispatchRaysIndex().xy, g_sceneCB.cameraPosition.xyz, g_sceneCB.projectionToWorld);

    float2 sampleSeed = DispatchRaysIndex().xy;
    float2 bufferDimension = DispatchRaysDimensions().xy;

    rng_state = sampleSeed.x + bufferDimension.x * sampleSeed.y;
    rng_state = uint(wang_hash(rng_state));


    //TODO improve to hemisphere sample
    float2 sampleUV = float2(rand_xorshift(), rand_xorshift());
    float3 rayDir = normalize(SquareToSphereUniform(sampleUV));
    //float3 rayDir = SamplePointLight(sampleUV);
    sampleUV *= 100;

    RayDesc rayDesc;
    rayDesc.Origin = g_sceneCB.lightPosition.xyz;
    rayDesc.Direction = rayDir;
    // Set TMin to a zero value to avoid aliasing artifcats along contact areas.
    // Note: make sure to enable back-face culling so as to avoid surface face fighting.
    rayDesc.TMin = 0;
    rayDesc.TMax = 10000;

    PhotonRayPayload rayPayload =
    {
        float3(0, 0, 0),    // hit position
        rayDir,             // ray direction 
        false,              // previous hit is specular
        float3(1, 1, 1),    // throughput
        0,                  // recursion depth
    };

    TraceRay(g_scene,
        RAY_FLAG_CULL_BACK_FACING_TRIANGLES,
        TraceRayParameters::InstanceMask,
        TraceRayParameters::HitGroup::Offset[RayType::Radiance],
        TraceRayParameters::HitGroup::GeometryStride,
        TraceRayParameters::MissShader::Offset[RayType::Radiance],
        rayDesc, rayPayload);

    // uint3 launchIndex = DispatchRaysIndex();
    // uint3 launchDimension = DispatchRaysDimensions();
    // int index = launchIndex.y * launchDimension.x + launchIndex.x;
    // Photon p = g_photons[index];
    //rayPayload.position = float3(1,0,0);

    //  int minBound = -50;
    // int maxBound = 50;
    // float cellSize = 0.2f;
    // int width = (maxBound - minBound) / cellSize;
    // float3 pos = (floor(rayPayload.position - minBound/ cellSize));
    // int index = pos.x + pos.y * 100 + pos.z * 100 *100;;
    // float3 color = float3(1,0,0);
    // if (index > 1) {
    //     color.y = 1;
    // }
    // g_renderTarget[DispatchRaysIndex().xy] = float4(pos,1);

}

//***************************************************************************
//******************------ Closest hit shaders -------***********************
//***************************************************************************

[shader("closesthit")]
void MyClosestHitShader_Triangle_Photon(inout PhotonRayPayload rayPayload, in BuiltInTriangleIntersectionAttributes attr)
{
    if (rayPayload.recursionDepth >= MAX_RAY_RECURSION_DEPTH) {
        return;
    }


    // Get the base index of the triangle's first 16 bit index.
    uint indexSizeInBytes = 2;
    uint indicesPerTriangle = 3;
    uint triangleIndexStride = indicesPerTriangle * indexSizeInBytes;
    uint baseIndex = PrimitiveIndex() * triangleIndexStride;

    // Load up three 16 bit indices for the triangle.
    const uint3 indices = Load3x16BitIndices(baseIndex, g_indices);

    // Retrieve corresponding vertex normals for the triangle vertices.
    float3 triangleNormal = g_vertices[indices[0]].normal;

    float niOvernt;
    float3 realNormal;

    float3 hitPosition = HitWorldPosition();

    //Ray newRay;
    float3 newThroughput = float3(1, 1, 1);
    float3 throughput = rayPayload.throughput;

    Ray shadowRay = { hitPosition, normalize(g_sceneCB.lightPosition.xyz - hitPosition) };
    bool shadowRayHit = TraceShadowRayAndReportIfHit(shadowRay, rayPayload.recursionDepth);

    //float russian_roulette_prob = max(throughput.x, max(throughput.y, throughput.z));
    //float threshold = rand_xorshift();
    
    //if (threshold >= russian_roulette_prob) {
    //    return;
    //}

    //newThroughput = throughput * 

  
    if (l_materialCB.refractCoef > 0.001) {
        float rayDotNormal = dot(WorldRayDirection(), triangleNormal);
        float temp = 1.5;
        if (rayDotNormal > 0.0) {
            realNormal = -triangleNormal;
            niOvernt = temp;
        }
        else {
            realNormal = triangleNormal;
            niOvernt = 1.0 / temp;
        }


        float cosine = dot(-WorldRayDirection(), realNormal);
        float discriminant = 1.0 - niOvernt * niOvernt * (1.0 - cosine * cosine);

        if (discriminant > 0) { //refract 

            float3 newDir = normalize(refract(WorldRayDirection(), realNormal, niOvernt));
            Ray newRay = { HitWorldPosition() + 0.01 * newDir, newDir};
            TracePhotonRay(newRay, rayPayload, rayPayload.recursionDepth, newThroughput, true);
            
        }
        else { // total reflect
            Ray newRay = { HitWorldPosition(), reflect(WorldRayDirection(), triangleNormal) };
            TracePhotonRay(newRay, rayPayload, rayPayload.recursionDepth, newThroughput, true);

        }
    }
    else if (l_materialCB.reflectanceCoef > 0.001) // reflect
    {
        // Trace a reflection ray.
        Ray newRay = { HitWorldPosition(), reflect(WorldRayDirection(), triangleNormal) };
        TracePhotonRay(newRay, rayPayload, rayPayload.recursionDepth, newThroughput, true);

    }
    else { //diffuse lambert
        if (rayPayload.prev_specular) {
            //store photon
            float4 phongColor = CalculatePhongLighting(l_materialCB.albedo, triangleNormal, shadowRayHit, l_materialCB.diffuseCoef, l_materialCB.specularCoef, l_materialCB.specularPower);
            Photon p = {throughput * phongColor * abs(dot(triangleNormal, normalize(g_sceneCB.lightPosition.xyz - hitPosition))), hitPosition, -rayPayload.direction, 0};
            Photon p = {throughput * phongColor * abs(dot(triangleNormal, normalize(g_sceneCB.lightPosition.xyz - hitPosition))), 0};

            StorePhoton(p);
        }
        //rayPayload.position = hitPosition;

    }

}

[shader("closesthit")]
void MyClosestHitShader_AABB_Photon(inout PhotonRayPayload rayPayload, in ProceduralPrimitiveAttributes attr)
{
    // PERFORMANCE TIP: it is recommended to minimize values carry over across TraceRay() calls. 
    // Therefore, in cases like retrieving HitWorldPosition(), it is recomputed every time.

    // Shadow component.
    // Trace a shadow ray.
    float3 hitPosition = HitWorldPosition();

    float niOvernt;
    float3 realNormal;

   // Ray newRay;
    float3 newThroughput = float3(1, 1, 1);
    float3 throughput = rayPayload.throughput;
    Ray shadowRay = { hitPosition, normalize(g_sceneCB.lightPosition.xyz - hitPosition) };
    bool shadowRayHit = TraceShadowRayAndReportIfHit(shadowRay, rayPayload.recursionDepth);

    //float russian_roulette_prob = max(throughput.x, max(throughput.y, throughput.z));
    //float threshold = rand_xorshift();

    //if (threshold >= russian_roulette_prob) {
    //    return;
    //}

    //newThroughput = throughput * 


    if (l_materialCB.refractCoef > 0.001) {
        float rayDotNormal = dot(WorldRayDirection(), attr.normal);
        float temp = 1.5;
        if (rayDotNormal > 0.0) {
            realNormal = -attr.normal;
            niOvernt = temp;
        }
        else {
            realNormal = attr.normal;
            niOvernt = 1.0 / temp;
        }


        float cosine = dot(-WorldRayDirection(), realNormal);
        float discriminant = 1.0 - niOvernt * niOvernt * (1.0 - cosine * cosine);

        if (discriminant > 0) { //refract 

            float3 newDir = normalize(refract(WorldRayDirection(), realNormal, niOvernt));
            Ray newRay = { HitWorldPosition() + 0.01 * newDir , newDir };         //���ʾ�������ô���ģ�����
            TracePhotonRay(newRay, rayPayload, rayPayload.recursionDepth, newThroughput, true);

        }
        else { // total reflect
            Ray newRay = { HitWorldPosition(), reflect(WorldRayDirection(), attr.normal) };
            TracePhotonRay(newRay, rayPayload, rayPayload.recursionDepth, newThroughput, true);

        }
        //rayPayload.position = hitPosition;

    }
    else if (l_materialCB.reflectanceCoef > 0.001) // reflect
    {
        // Trace a reflection ray.
        Ray newRay = { HitWorldPosition(), reflect(WorldRayDirection(), attr.normal) };
        TracePhotonRay(newRay, rayPayload, rayPayload.recursionDepth, newThroughput, true);


    }
    else { //diffuse lambert
        if (rayPayload.prev_specular) {
            //store photon
            float4 phongColor = CalculatePhongLighting(l_materialCB.albedo, attr.normal, shadowRayHit, l_materialCB.diffuseCoef, l_materialCB.specularCoef, l_materialCB.specularPower);
            Photon p = {throughput * phongColor * abs(dot(attr.normal, normalize(g_sceneCB.lightPosition.xyz - hitPosition))), hitPosition, -rayPayload.direction, 0};
            StorePhoton(p);
        }

    }
}

//***************************************************************************
//**********************------ Miss shaders -------**************************
//***************************************************************************

[shader("miss")]
void MyMissShader_Photon(inout PhotonRayPayload rayPayload)
{
    rayPayload.position = float3(0, 0, 0);
}

[shader("miss")]
void MyMissShader_ShadowRay_Photon(inout ShadowRayPayload rayPayload)
{
    rayPayload.hit = false;
}

//***************************************************************************
//*****************------ Intersection shaders-------************************
//***************************************************************************

// Get ray in AABB's local space.
Ray GetRayInAABBPrimitiveLocalSpace()
{
    PrimitiveInstancePerFrameBuffer attr = g_AABBPrimitiveAttributes[l_aabbCB.instanceIndex];

    // Retrieve a ray origin position and direction in bottom level AS space 
    // and transform them into the AABB primitive's local space.
    Ray ray;
    ray.origin = mul(float4(ObjectRayOrigin(), 1), attr.bottomLevelASToLocalSpace).xyz;
    ray.direction = mul(ObjectRayDirection(), (float3x3) attr.bottomLevelASToLocalSpace);
    return ray;
}

[shader("intersection")]
void MyIntersectionShader_AnalyticPrimitive_Photon()
{
    Ray localRay = GetRayInAABBPrimitiveLocalSpace();
    AnalyticPrimitive::Enum primitiveType = (AnalyticPrimitive::Enum)l_aabbCB.primitiveType;

    float thit;
    ProceduralPrimitiveAttributes attr = (ProceduralPrimitiveAttributes)0;
    if (RayAnalyticGeometryIntersectionTest(localRay, primitiveType, thit, attr))
    {
        PrimitiveInstancePerFrameBuffer aabbAttribute = g_AABBPrimitiveAttributes[l_aabbCB.instanceIndex];
        attr.normal = mul(attr.normal, (float3x3) aabbAttribute.localSpaceToBottomLevelAS);
        attr.normal = normalize(mul((float3x3) ObjectToWorld3x4(), attr.normal));

        ReportHit(thit, /*hitKind*/ 0, attr);
    }
}

[shader("intersection")]
void MyIntersectionShader_VolumetricPrimitive_Photon()
{
    Ray localRay = GetRayInAABBPrimitiveLocalSpace();
    VolumetricPrimitive::Enum primitiveType = (VolumetricPrimitive::Enum)l_aabbCB.primitiveType;

    float thit;
    ProceduralPrimitiveAttributes attr = (ProceduralPrimitiveAttributes)0;
    if (RayVolumetricGeometryIntersectionTest(localRay, primitiveType, thit, attr, g_sceneCB.elapsedTime))
    {
        PrimitiveInstancePerFrameBuffer aabbAttribute = g_AABBPrimitiveAttributes[l_aabbCB.instanceIndex];
        attr.normal = mul(attr.normal, (float3x3) aabbAttribute.localSpaceToBottomLevelAS);
        attr.normal = normalize(mul((float3x3) ObjectToWorld3x4(), attr.normal));

        ReportHit(thit, /*hitKind*/ 0, attr);
    }
}

[shader("intersection")]
void MyIntersectionShader_SignedDistancePrimitive_Photon()
{
    Ray localRay = GetRayInAABBPrimitiveLocalSpace();
    SignedDistancePrimitive::Enum primitiveType = (SignedDistancePrimitive::Enum)l_aabbCB.primitiveType;

    float thit;
    ProceduralPrimitiveAttributes attr = (ProceduralPrimitiveAttributes)0;
    if (RaySignedDistancePrimitiveTest(localRay, primitiveType, thit, attr, l_materialCB.stepScale))
    {
        PrimitiveInstancePerFrameBuffer aabbAttribute = g_AABBPrimitiveAttributes[l_aabbCB.instanceIndex];
        attr.normal = mul(attr.normal, (float3x3) aabbAttribute.localSpaceToBottomLevelAS);
        attr.normal = normalize(mul((float3x3) ObjectToWorld3x4(), attr.normal));

        ReportHit(thit, /*hitKind*/ 0, attr);
    }
}

#endif // RAYTRACING_HLSL
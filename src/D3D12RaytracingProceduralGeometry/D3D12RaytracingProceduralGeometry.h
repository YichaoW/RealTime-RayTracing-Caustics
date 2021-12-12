//*********************************************************
//
// Copyright (c) Microsoft. All rights reserved.
// This code is licensed under the MIT License (MIT).
// THIS CODE IS PROVIDED *AS IS* WITHOUT WARRANTY OF
// ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING ANY
// IMPLIED WARRANTIES OF FITNESS FOR A PARTICULAR
// PURPOSE, MERCHANTABILITY, OR NON-INFRINGEMENT.
//
//*********************************************************

#pragma once

#include "DXSample.h"
#include "StepTimer.h"
#include "RaytracingSceneDefines.h"
#include "DirectXRaytracingHelper.h"
#include "PerformanceTimers.h"

class D3D12RaytracingProceduralGeometry : public DXSample
{
public:
    D3D12RaytracingProceduralGeometry(UINT width, UINT height, std::wstring name);

    // IDeviceNotify
    virtual void OnDeviceLost() override;
    virtual void OnDeviceRestored() override;

    // Messages
    virtual void OnInit();
    virtual void OnKeyDown(UINT8 key);
    virtual void OnUpdate();
    virtual void OnRender();
    virtual void OnSizeChanged(UINT width, UINT height, bool minimized);
    virtual void OnDestroy();
    virtual IDXGISwapChain* GetSwapchain() { return m_deviceResources->GetSwapChain(); }

private:
    static const UINT FrameCount = 3;

    // Constants.
    const UINT NUM_BLAS = 2;          // Triangle + AABB bottom-level AS.
    const float c_aabbWidth = 2;      // AABB width.
    const float c_aabbDistance = 2;   // Distance between AABBs.


    //Photon Mapping
    static const UINT NUM_GBUFFERS = 4;
    static const UINT NUM_RENDERTARGETS = 1;
    static const UINT NUM_PHOTONS = PHOTON_NUM;
    static const UINT PHOTONMAP_WIDTH = 1024;
    static const UINT PHOTONMAP_HEIGHT = NUM_PHOTONS / PHOTONMAP_WIDTH;
    
    // DirectX Raytracing (DXR) attributes
    ComPtr<ID3D12Device5> m_dxrDevice;
    ComPtr<ID3D12GraphicsCommandList5> m_dxrCommandList;

    // DXR resources for each pipeline
    struct DXRResource {
        // DirectX Raytracing (DXR) attributes
        ComPtr<ID3D12StateObject> dxrStateObject;

        // Root signatures
        ComPtr<ID3D12RootSignature> globalRootSignature;
        ComPtr<ID3D12RootSignature> localRootSignature[LocalRootSignature::Type::Count];

        // Shader tables
        ComPtr<ID3D12Resource> missShaderTable;
        UINT missShaderTableStrideInBytes = UINT_MAX;
        ComPtr<ID3D12Resource> hitGroupShaderTable;
        UINT hitGroupShaderTableStrideInBytes = UINT_MAX;
        ComPtr<ID3D12Resource> rayGenShaderTable;
    };

    DXRResource m_raytracing_res;
    DXRResource m_photontracing_res;

    
    // Root signatures
    // ComPtr<ID3D12RootSignature> m_raytracingGlobalRootSignature;
    // ComPtr<ID3D12RootSignature> m_raytracingLocalRootSignature[LocalRootSignature::Type::Count];

    // Descriptors
    ComPtr<ID3D12DescriptorHeap> m_descriptorHeap;
    UINT m_descriptorsAllocated;
    UINT m_descriptorSize;

    // Raytracing scene
    ConstantBuffer<SceneConstantBuffer> m_sceneCB;
    StructuredBuffer<PrimitiveInstancePerFrameBuffer> m_aabbPrimitiveAttributeBuffer;
    std::vector<D3D12_RAYTRACING_AABB> m_aabbs;

    // Root constants
    PrimitiveConstantBuffer m_planeMaterialCB;
    PrimitiveConstantBuffer m_glassMaterialCB;
    PrimitiveConstantBuffer m_aabbMaterialCB[IntersectionShaderType::TotalPrimitiveCount];

    // Geometry
    D3DBuffer m_indexBuffer;
    D3DBuffer m_vertexBuffer;

    D3DBuffer m_aabbBuffer;

    // Acceleration structure
    ComPtr<ID3D12Resource> m_bottomLevelAS[BottomLevelASType::Count];
    ComPtr<ID3D12Resource> m_topLevelAS;

    // Raytracing output
    ComPtr<ID3D12Resource> m_raytracingOutput;
    D3D12_GPU_DESCRIPTOR_HANDLE m_raytracingOutputResourceUAVGpuDescriptor;
    UINT m_raytracingOutputResourceUAVDescriptorHeapIndex;

    // Photon Map
    ComPtr<ID3D12Resource> m_photonMap;
    D3D12_GPU_DESCRIPTOR_HANDLE m_photonMapResourceUAVGpuDescriptor;
    UINT m_photonMapResourceUAVDescriptorHeapIndex;
    bool hasPhotonMap = false;

    // Shader tables
    static const wchar_t* c_hitGroupNames_TriangleGeometry[RayType::Count];
    static const wchar_t* c_hitGroupNames_AABBGeometry[IntersectionShaderType::Count][RayType::Count];
    static const wchar_t* c_raygenShaderName;
    static const wchar_t* c_intersectionShaderNames[IntersectionShaderType::Count];
    static const wchar_t* c_closestHitShaderNames[GeometryType::Count];
    static const wchar_t* c_missShaderNames[RayType::Count];

    static const wchar_t* c_hitGroupNames_TriangleGeometry_photon[RayType::Count];
    static const wchar_t* c_hitGroupNames_AABBGeometry_photon[IntersectionShaderType::Count][RayType::Count];
    static const wchar_t* c_raygenShaderName_photon;
    static const wchar_t* c_intersectionShaderNames_photon[IntersectionShaderType::Count];
    static const wchar_t* c_closestHitShaderNames_photon[GeometryType::Count];
    static const wchar_t* c_missShaderNames_photon[RayType::Count];
    
    // load model
    std::vector<Vertex> m_vertices;
    std::vector<Index> m_indices;

    // Application state
    DX::GPUTimer m_gpuTimers[GpuTimers::Count];
    StepTimer m_timer;
    float m_animateGeometryTime;
    bool m_animateGeometry;
    bool m_animateCamera;
    bool m_animateLight;
    XMVECTOR m_eye;
    XMVECTOR m_at;
    XMVECTOR m_up;



    void UpdateCameraMatrices();
    void UpdateAABBPrimitiveAttributes(float animationTime);
    void InitializeScene();
    void RecreateD3D();
    void DoRaytracing();
    //Photon 
    void DoPhotontracing();
    void CreatePhotonGBuffers();

    
    void CreateConstantBuffers();
    void CreateAABBPrimitiveAttributesBuffers();
    void CreateDeviceDependentResources();
    void CreateWindowSizeDependentResources();
    void ReleaseDeviceDependentResources();
    void ReleaseWindowSizeDependentResources();
    void CreateRaytracingInterfaces();
    void SerializeAndCreateRaytracingRootSignature(D3D12_ROOT_SIGNATURE_DESC& desc, ComPtr<ID3D12RootSignature>* rootSig);
    void CreateRootSignatures();
    void CreatePhotonRootSignatures();
    void CreateDxilLibrarySubobject(CD3DX12_STATE_OBJECT_DESC* raytracingPipeline);
    void CreatePhotonDxilLibrarySubobject(CD3DX12_STATE_OBJECT_DESC* raytracingPipeline);
    void CreateHitGroupSubobjects(CD3DX12_STATE_OBJECT_DESC* raytracingPipeline);
    void CreatePhotonHitGroupSubobjects(CD3DX12_STATE_OBJECT_DESC* raytracingPipeline); // photon tracing
    void CreateLocalRootSignatureSubobjects(CD3DX12_STATE_OBJECT_DESC* raytracingPipeline);
    void CreatePhotonLocalRootSignatureSubobjects(CD3DX12_STATE_OBJECT_DESC* raytracingPipeline);
    void CreateRaytracingPipelineStateObject();
    void CreatePhotontracingPipelineStateObject();
    void CreateAuxilaryDeviceResources();
    void CreateDescriptorHeap();
    void CreateRaytracingOutputResource();
    void BuildProceduralGeometryAABBs();
    void BuildGeometry();
    void BuildPlaneGeometry();
    void LoadModel(std::string filepath, XMFLOAT3 scale, XMFLOAT3 translation);
    void CreateVertexIndexBuffers();
    void BuildGeometryDescsForBottomLevelAS(std::array<std::vector<D3D12_RAYTRACING_GEOMETRY_DESC>, BottomLevelASType::Count>& geometryDescs);
    template <class InstanceDescType, class BLASPtrType>
    void BuildBotomLevelASInstanceDescs(BLASPtrType *bottomLevelASaddresses, ComPtr<ID3D12Resource>* instanceDescsResource);
    AccelerationStructureBuffers BuildBottomLevelAS(const std::vector<D3D12_RAYTRACING_GEOMETRY_DESC>& geometryDesc, D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BUILD_FLAGS buildFlags = D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BUILD_FLAG_PREFER_FAST_TRACE);
    AccelerationStructureBuffers BuildTopLevelAS(AccelerationStructureBuffers bottomLevelAS[BottomLevelASType::Count], D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BUILD_FLAGS buildFlags = D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BUILD_FLAG_PREFER_FAST_TRACE);
    void BuildAccelerationStructures();
    void BuildShaderTables(); // raytracing
    void BuildPhotonShaderTables(); // photontracing
    void UpdateForSizeChange(UINT clientWidth, UINT clientHeight);
    void CopyPhotonMapToBackbuffer();
    void CopyRaytracingOutputToBackbuffer();
    void CalculateFrameStats();
    UINT AllocateDescriptor(D3D12_CPU_DESCRIPTOR_HANDLE* cpuDescriptor, UINT descriptorIndexToUse = UINT_MAX);
    UINT CreateBufferSRV(D3DBuffer* buffer, UINT numElements, UINT elementSize);
};

# RealTime-RayTracing-Caustics

## Overview

### Caustics
Caustic is the term used to describe the patterns of light and color that occur when light rays are reflected or refracted from a surface.

![](img/realGlassCaustics.jpg) 
![](img/realWaterCaustics.jpg)

The above two images are the caustics from glass and water in real life.

### Cool Results

#### Live Demo

![](img/scene1.gif)

![](img/scene2.gif)

| Starbucks Coffee Cup | Chalice | 
|----|----|
|![cc41592d8df132130e5f6564a5a1be7](https://user-images.githubusercontent.com/66859615/145743478-7e5a9f43-6805-4c3b-8c47-5619bd7df51f.png)|![d39186e6aacdb299692a544b7c4aed2](https://user-images.githubusercontent.com/66859615/145743493-6e38d61d-3f1e-41f7-9979-2892d9adf65e.png)|

| Utah Teapot | Cat| 
|----|----|
|![bb31e063d4e81ed3a6a8f7e2a022373](https://user-images.githubusercontent.com/66859615/145743504-a286e6ba-c1b7-4b22-b907-e2b807e5c8ea.png) | ![](img/cat.PNG)|

#### Water

![](img/water.PNG)

### Project Implementation

This project implements real-time ray tracing techniques for rendering caustics effects using [DirectX RayTracing(DXR)](#directx-raytracing(dxr)). The main idea to visualize caustics is to use photon tracing. Caustics are commonly seen in water, metallic, and transparent surfaces but they are either ignored or roughly handled such as decal textures. GPU ray tracing brings photon mapping which is currently most efficient algorithm to calculate caustics pattern. We used several research papers to guide us to produce the final result. See [References](#references).

### Requirement

* Windows 10
* Visual Studio 2019
* DirectX RayTracing(DXR)
* GeForce GTX 1060

## Presentation Slides
[Pitch Slides](https://docs.google.com/presentation/d/1REs8Hu2autTPQMAH6XG6zNYCJJKy6ZIw7h2XxpiPR0Q/edit?usp=sharing)

[Milestone1 Slides](https://docs.google.com/presentation/d/1B7V_mOnpXrHAl32jmDtPGyeIjG3wCJcU7zVgILual1E/edit?usp=sharing)

[Milestone2 Slides](https://docs.google.com/presentation/d/1bBe-m0S8USm9JjuZ0aMPiBgOyF8d1e4xpH3DJyMze_Q/edit?usp=sharing)

[Milestone3 Slides](https://docs.google.com/presentation/d/1QpMr9G-N3W1MqqeVK1NEGOBwIfzCrvPcZRigRFSnQKE/edit?usp=sharing)

## DirectX RayTracing

DirectX RayTracing (DXR) is a feature introduced in Microsoft's DirectX 12 API that implements ray tracing. We are using base code from [Microsft's DXR samples](https://github.com/microsoft/DirectX-Graphics-Samples/tree/master/Samples/Desktop/D3D12Raytracing/src/D3D12RaytracingProceduralGeometry).

## Photon Mapping

Photon mapping realistically simulates the interaction of light with different types of objects. We emit photons from the light and record its intersection and throughput to build the photon map. Then we use the normal ray tracing to accumulate photons near the hit position.

## Photon Caustics

Caustics photon map is slightly different from traditional photon map. For caustics, we only store photons that hit a diffuse object and its previous hit is a specular object. After that, we compute the caustics through ray tracing.

### Sphere
| Refraction Sphere| Refraction Sphere with caustics |
|----|----|
| ![](img/sphereRefract.PNG) | ![](img/sphereNaive.PNG)|

### Cube
| Refraction Cube| Refraction Cube with Photon Visualization| 
|----|----|
|![1884c430f96104aae22d4216a4313e2](https://user-images.githubusercontent.com/66859615/145742006-e353051f-e481-42d1-8a2d-3fffeb0e47af.png) | ![a568c9ba31f0b17cabcd576b269d816](https://user-images.githubusercontent.com/66859615/145742134-e3379a14-16cb-47a4-9280-2bb5ab122fba.png)|

| Naive k nearest neightbor| Spatial Hashing 1| 
|----|----|
|![871a2f749906c051b73b73ee0172944](https://user-images.githubusercontent.com/66859615/145742172-cb66d801-290a-4276-b291-d501b772088e.png) | ![e897172f6213197d2b6b428ce81b102](https://user-images.githubusercontent.com/66859615/145742463-e80bdb45-b5d1-466c-8181-74bb3ace6657.png)|

| Spatial Hashing 2| Real Life Reference image | 
|----|----|
| ![82ec8afde0e77b5b89910495c3bc136](https://user-images.githubusercontent.com/66859615/145742524-4584380e-65bb-4457-b1b0-d06becc2dfd2.png)|![e9e2808e5e26dc4ef2435b5d28d24d5](https://user-images.githubusercontent.com/66859615/145742838-c5fb438d-0cd0-4d80-a4df-856891256982.png) |



## Naive Search

They are several algorithms to accumulate caustic photons near the hit position. The first one is the naive search which accumulates all the photons within a predefined search radius. This algorithm is easy to implement but it has several drawbacks. First of all, it produces an unnatural visual effect. As we can see from the below image, there are artificial circles surrounding the caustics. This may be caused by the predefined search radius. Another disadvantage is that this algorithm is not very efficient. Since it traverses all the photons to find nearby ones at each hit position, the time complexity is O(N), where N is the number of photons we emit.

### Naive Caustics
![](img/naive1.PNG)

## Stochastic Spatial Hashing

Another algorithm we implemented is the stochastic hash where we store photons in a hash table. In this algorithm, we separate 3D space into small cells. Each cell. For each photon's position, we compute the cell it belongs to and hash it into the hash table. If there is more than one photon's at the same index, we just accumulate the photon count. Then we search for neighbors to compute final caustics at each hit position. This method increases variance since it ignores a lot of photons. This also introduces some noise to the final image. However, the results looks more natural, as we can see from the below image. This algorithm is also a lot more efficient than naive search. The time complexity is O(1) since we only need to find its neighbor.

### Stochastic Spatial Hashing Caustics

![](img/sphereSpatial.PNG)


## Performance Analysis

All the performance test is run by GeForce GTX 1060. It will be much faster if use advance graphics cards such as GeForce RTX 3060 and above.

Note that the fps for sphere without caustics is about 300fps.

### Naive Search

The number of photons will affect both fps and the visual effect in naive search. We can see both performance is unsatisfactory from the below images.

| 2^12 photons(15 fps) | 2^12 photons(11 fps) |2^12 photons(8 fps) |
|---|---|---|
|![](img/naive1.PNG) | ![](img/naive3.PNG) | ![](img/naive2.PNG) |

### Spatial Hashing

#### Number of Photons

Like naive search, the number of photons will also affect both fps and the visual effect in sptial hashing though it is a lot faster with more photons. As number of photon increase, the caustics area increases. 

| 2^18 photons (37 fps) | 2^22 photons (25 fps) |2^24 photons (20 fps) |
|---|---|---|
|![](img/sh2.PNG) | ![](img/sh1.PNG) | ![](img/sphereSpatial.PNG) |

Note that the cell size is 0.02^3 for above images.

#### Cell Size

As spatial grid's cell size increases, the caustics area increases and the fps also increases. Since grid size is fixed, increase of cell size means decrease the number of cells in the grid. Thus the fps increases.

| 0.02^3 cell size(20 fps)| 0.1^3 cell size (42 fps)|0.1^3 cell size (84 fps) |
|----|----|----|
| ![](img/sphereSpatial.PNG)|![](img/cs2.PNG) | ![](img/cs1.PNG)|

Note that the photon number is 2^24 for above images.


## Future Work
* GPU KD Tree nearest neighbor search, spatial hashing is a good estimation but not detailed enough
* Support more model import, including mtl, gltf. Make the DXR pipeline more efficient with large models
* Raytracing and photon tracing with more bounces and indirect light to improve overall quality

## References

[Real-Time Raytraced Caustics](https://link.springer.com/content/pdf/10.1007%2F978-1-4842-7185-8_30.pdf)

[Microsft's DXR samples](https://github.com/microsoft/DirectX-Graphics-Samples/tree/master/Samples/Desktop/D3D12Raytracing/src/D3D12RaytracingProceduralGeometry)

[Photon Mapping](https://graphics.stanford.edu/courses/cs348b-00/course8.pdf)

[Photon Mapping GPU](https://cs.uwaterloo.ca/~thachisu/gpuppm_slides.pdf)

[Progressive Photon Mapping on GPUs](https://apartridge.github.io/OppositeRenderer/master/masteroppgave.pdf)

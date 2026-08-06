//
//  ARMeshGeometry.swift
//  Hijauin
//
//  Created by Reynard Amadeus  on 06/08/26.
//

//  Low-level helpers for reading raw geometry out of an ARMeshAnchor.
//
//  ARKit exposes mesh data as packed Metal buffers, not Swift arrays.
//  These helpers decode vertices, face indices, and per-face classification
//  so higher-level code can work with SIMD values instead of raw pointers.
//

import ARKit
 
extension ARMeshGeometry {
 
    /// World-independent (anchor-local) position of a vertex.
    func vertex(at index: UInt32) -> SIMD3<Float> {
        assert(vertices.format == .float3, "Expected three-component float vertices.")
        let pointer = vertices.buffer.contents()
            .advanced(by: vertices.offset + vertices.stride * Int(index))
        return pointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
    }
 
    /// The vertex indices making up one triangular face.
    func vertexIndices(ofFace faceIndex: Int) -> [UInt32] {
        let indicesPerFace = faces.indexCountPerPrimitive        // 3 for triangles
        let base = faces.buffer.contents()
        var result = [UInt32]()
        result.reserveCapacity(indicesPerFace)
        for i in 0..<indicesPerFace {
            let pointer = base.advanced(
                by: (faceIndex * indicesPerFace + i) * faces.bytesPerIndex
            )
            result.append(pointer.assumingMemoryBound(to: UInt32.self).pointee)
        }
        return result
    }
 
    /// Centroid of a face in anchor-local space. Cheaper to cluster on than
    /// three separate vertices and stable enough for obstacle detection.
    func centroid(ofFace faceIndex: Int) -> SIMD3<Float> {
        let idx = vertexIndices(ofFace: faceIndex)
        let a = vertex(at: idx[0])
        let b = vertex(at: idx[1])
        let c = vertex(at: idx[2])
        return (a + b + c) / 3.0
    }
 
    /// ARKit's semantic label for a face (floor, table, wall, seat, …).
    /// Returns `.none` when the session wasn't run with `.meshWithClassification`.
    func classification(ofFace faceIndex: Int) -> ARMeshClassification {
        guard let classification = classification else { return .none }
        let pointer = classification.buffer.contents()
            .advanced(by: classification.offset + classification.stride * faceIndex)
        let raw = Int(pointer.assumingMemoryBound(to: UInt8.self).pointee)
        return ARMeshClassification(rawValue: raw) ?? .none
    }
}
 
extension SIMD4 where Scalar == Float {
    /// Drop the homogeneous component (used when applying a 4x4 transform).
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}
 
extension simd_float4x4 {
    /// Transform an anchor-local point into world space.
    func transformPoint(_ p: SIMD3<Float>) -> SIMD3<Float> {
        (self * SIMD4<Float>(p.x, p.y, p.z, 1)).xyz
    }

    /// Camera/entity forward direction (RealityKit looks down local -Z).
    var forward: SIMD3<Float> { -columns.2.xyz }
    
    var position: SIMD3<Float> { columns.3.xyz }
}

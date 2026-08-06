//
//  TabletopObstacleDetector.swift
//  Hijauin
//
//  Created by Reynard Amadeus  on 06/08/26.
//

//  Detects discrete objects sitting on a plane (the table) from the LiDAR
//  scene-reconstruction mesh and returns each as an axis-aligned bounding box.
//
//  Pipeline:
//    1. Keep only mesh faces above the table plane and within its footprint.
//    2. Voxel-hash the surviving world-space centroids.
//    3. Union adjacent occupied voxels → connected components (one per object).
//    4. Emit an AABB per component large enough to act as a nav obstacle.
//
//  Nothing here touches RealityKit; it is pure geometry so it can be unit-tested.
//
 
import ARKit
import simd
 

struct TabletopObstacleDetector {
 
    // MARK: Tunables
 
    /// Ignore anything within this height of the tabletop — rejects the table
    /// surface itself plus sensor noise. Raise if the table edge leaks through.
    var minHeightAbovePlane: Float = 0.015          // 1.5 cm
 
    /// Discard anything taller than this above the table (people, walls behind).
    var maxHeightAbovePlane: Float = 0.60           // 60 cm
 
    /// Voxel size for clustering. Roughly the LiDAR resolution; also the gap at
    /// which two objects are treated as one. ~3 cm separates typical props well.
    var voxelSize: Float = 0.03
 
    /// Reject clusters with fewer supporting faces than this (noise speckle).
    var minPointsPerObstacle: Int = 6
 
    /// Pad each box outward so the robot keeps clearance from coarse geometry.
    var obstaclePadding: Float = 0.01               // 1 cm on every side
 
    // MARK: Detection
 
    func detectObstacles(
        in meshAnchors: [ARMeshAnchor],
        on plane: TablePlane
    ) -> [RealObstacle] {
 
        // 1. Collect qualifying world-space face centroids from every anchor.
        var points: [SIMD3<Float>] = []
        for anchor in meshAnchors {
            let geometry = anchor.geometry
            let transform = anchor.transform
            for faceIndex in 0..<geometry.faces.count {
                // Skip faces ARKit already knows are floor/wall/table.
                switch geometry.classification(ofFace: faceIndex) {
                case .floor, .wall, .ceiling, .table: continue
                default: break
                }
                let localCentroid = geometry.centroid(ofFace: faceIndex)
                let world = transform.transformPoint(localCentroid)
                guard isOnTable(world, plane) else { continue }
                points.append(world)
            }
        }
        guard !points.isEmpty else { return [] }
 
        // 2 + 3. Voxel hash → union-find connected components.
        let clusters = clusterByVoxelConnectivity(points)
 
        // 4. One padded AABB per surviving cluster.
        return clusters.compactMap { boundingBox(of: $0) }
    }
 
    // MARK: Filtering
 
    private func isOnTable(_ p: SIMD3<Float>, _ plane: TablePlane) -> Bool {
        let dh = p.y - plane.height
        guard dh > minHeightAbovePlane, dh < maxHeightAbovePlane else { return false }
        let dx = abs(p.x - plane.center.x)
        let dz = abs(p.z - plane.center.y)
        return dx <= plane.halfExtent.x && dz <= plane.halfExtent.y
    }
 
    // MARK: Clustering
 
    private struct VoxelKey: Hashable { let x, y, z: Int }
 
    private func voxelKey(_ p: SIMD3<Float>) -> VoxelKey {
        VoxelKey(
            x: Int(floor(p.x / voxelSize)),
            y: Int(floor(p.y / voxelSize)),
            z: Int(floor(p.z / voxelSize))
        )
    }
 
    /// Groups points whose voxels touch (26-neighborhood) into clusters.
    private func clusterByVoxelConnectivity(_ points: [SIMD3<Float>]) -> [[SIMD3<Float>]] {
        // Bucket points into voxels.
        var buckets: [VoxelKey: [SIMD3<Float>]] = [:]
        for p in points { buckets[voxelKey(p), default: []].append(p) }
 
        // Union-find over occupied voxels.
        let keys = Array(buckets.keys)
        var indexOf: [VoxelKey: Int] = [:]
        for (i, k) in keys.enumerated() { indexOf[k] = i }
        var parent = Array(0..<keys.count)
 
        func find(_ a: Int) -> Int {
            var a = a
            while parent[a] != a { parent[a] = parent[parent[a]]; a = parent[a] }
            return a
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }
 
        for (i, key) in keys.enumerated() {
            for dx in -1...1 { for dy in -1...1 { for dz in -1...1 {
                if dx == 0 && dy == 0 && dz == 0 { continue }
                let neighbor = VoxelKey(x: key.x + dx, y: key.y + dy, z: key.z + dz)
                if let j = indexOf[neighbor] { union(i, j) }
            }}}
        }
 
        // Gather points by cluster root.
        var clusters: [Int: [SIMD3<Float>]] = [:]
        for (i, key) in keys.enumerated() {
            clusters[find(i), default: []].append(contentsOf: buckets[key]!)
        }
        return Array(clusters.values)
    }
 
    // MARK: Bounding box
 
    private func boundingBox(of cluster: [SIMD3<Float>]) -> RealObstacle? {
        guard cluster.count >= minPointsPerObstacle else { return nil }
 
        var lo = cluster[0], hi = cluster[0]
        for p in cluster {
            lo = simd_min(lo, p)
            hi = simd_max(hi, p)
        }
        let pad = SIMD3<Float>(repeating: obstaclePadding)
        lo -= pad; hi += pad
 
        let center = (lo + hi) * 0.5
        var extents = hi - lo
        extents = simd_max(extents, SIMD3<Float>(repeating: 0.01)) // avoid zero-thin boxes
 
        return RealObstacle(center: center, extents: extents, pointCount: cluster.count)
    }
}

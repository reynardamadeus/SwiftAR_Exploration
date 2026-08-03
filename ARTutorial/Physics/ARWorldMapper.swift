//
//  ARWorldMapper.swift
//  ARTutorial
//
//  Turns the scanned real world into a physics map the robot can navigate:
//
//    • Horizontal planes  → "land": flat, walkable static collision (green).
//    • Reconstructed mesh  → "obstacles": static mesh collision for everything the
//                            scanner classifies as NOT floor (walls, furniture,
//                            props) shown in red. Floor faces are skipped because
//                            the planes already provide the ground.
//
//  Because every piece is a `PhysicsBodyComponent(mode: .static)` with a matching
//  `CollisionComponent`, the same robot control + physics behave in the real world:
//  it walks on the land, steps over low props (< 1/4 its height), collides with
//  tall obstacles, and falls off real ledges.
//
//  Two things that matter for this to actually work:
//   1. The ARSessionDelegate methods MUST stay synchronous (that's what the protocol
//      declares). We fan the async resource generation out into `Task`s. If these are
//      made `async`, ARKit silently stops calling them and nothing gets mapped.
//   2. We anchor mapped geometry by WORLD transform (not `AnchorEntity(anchor:)`),
//      because taking over the session delegate displaces ARView's own ARKit-anchor
//      tracking — world-anchored entities don't depend on it.
//
//  Requires a LiDAR device and scene reconstruction with classification.
//

import RealityKit
import ARKit
import UIKit
import QuartzCore

final class ARWorldMapper: NSObject, ARSessionDelegate {

    weak var arView: ARView?

    /// One world-anchored entity per ARKit anchor we've mapped.
    private var mapped: [UUID: AnchorEntity] = [:]
    /// Throttle: last time (per anchor) we rebuilt its (expensive) mesh collision.
    private var lastMeshBuild: [UUID: TimeInterval] = [:]
    private let meshRebuildInterval: TimeInterval = 0.75

    private let landMaterial = SimpleMaterial(color: UIColor.systemGreen.withAlphaComponent(0.45), isMetallic: false)
    private let obstacleMaterial = SimpleMaterial(color: UIColor.systemRed.withAlphaComponent(0.5), isMetallic: false)
    private let staticPhysics = PhysicsMaterialResource.generate(friction: 0.85, restitution: 0.0)

    // MARK: - ARSessionDelegate (must be synchronous to be called by ARKit)

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors { schedule(anchor) }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors { schedule(anchor) }
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        let ids = anchors.map { $0.identifier }
        Task { @MainActor in
            for id in ids {
                mapped.removeValue(forKey: id)?.removeFromParent()
                lastMeshBuild.removeValue(forKey: id)
            }
        }
    }

    // MARK: - Routing

    private func schedule(_ anchor: ARAnchor) {
        if let mesh = anchor as? ARMeshAnchor {
            Task { await updateMesh(mesh) }
        } else if let plane = anchor as? ARPlaneAnchor, plane.alignment == .horizontal {
            Task { @MainActor in updatePlane(plane) }
        }
    }

    // MARK: - Planes (land)

    @MainActor
    private func updatePlane(_ plane: ARPlaneAnchor) {
        guard let arView else { return }

        let anchorEntity: AnchorEntity
        if let existing = mapped[plane.identifier] {
            anchorEntity = existing
            anchorEntity.transform = Transform(matrix: plane.transform)
            anchorEntity.children.removeAll()
        } else {
            anchorEntity = AnchorEntity(world: plane.transform)
            mapped[plane.identifier] = anchorEntity
            arView.scene.addAnchor(anchorEntity)
        }

        let size = SIMD3<Float>(plane.planeExtent.width, 0.004, plane.planeExtent.height)
        let land = ModelEntity(mesh: .generateBox(size: size), materials: [landMaterial])
        land.position = plane.center
        let shape = ShapeResource.generateBox(size: size)
        land.components.set(CollisionComponent(shapes: [shape]))
        land.components.set(PhysicsBodyComponent(shapes: [shape], mass: 1, material: staticPhysics, mode: .static))
        anchorEntity.addChild(land)
    }

    // MARK: - Mesh (obstacles)

    @MainActor
    private func updateMesh(_ meshAnchor: ARMeshAnchor) async {
        guard let arView else { return }

        let now = CACurrentMediaTime()
        if let last = lastMeshBuild[meshAnchor.identifier], now - last < meshRebuildInterval { return }
        lastMeshBuild[meshAnchor.identifier] = now

        guard let data = obstacleGeometry(from: meshAnchor.geometry),
              data.positions.count <= 65_535 else { return }

        // Async resource generation (iOS 18 APIs are async throws).
        let faceIndices16 = data.indices.map { UInt16($0) }
        guard let collisionShape = try? await ShapeResource.generateStaticMesh(
            positions: data.positions, faceIndices: faceIndices16
        ) else { return }

        let anchorEntity: AnchorEntity
        if let existing = mapped[meshAnchor.identifier] {
            anchorEntity = existing
            anchorEntity.transform = Transform(matrix: meshAnchor.transform)
            anchorEntity.children.removeAll()
        } else {
            anchorEntity = AnchorEntity(world: meshAnchor.transform)
            mapped[meshAnchor.identifier] = anchorEntity
            arView.scene.addAnchor(anchorEntity)
        }

        let obstacle = ModelEntity()
        if let visual = try? await MeshResource.generate(from: [meshDescriptor(from: data)]) {
            obstacle.model = ModelComponent(mesh: visual, materials: [obstacleMaterial])
        }
        obstacle.components.set(CollisionComponent(shapes: [collisionShape]))
        obstacle.components.set(PhysicsBodyComponent(shapes: [collisionShape], mass: 1, material: staticPhysics, mode: .static))
        anchorEntity.addChild(obstacle)
    }

    // MARK: - Geometry extraction

    private struct MeshData {
        var positions: [SIMD3<Float>]
        var indices: [UInt32]
    }

    /// Builds a sub-mesh of every face that is NOT classified as floor. Vertices are
    /// re-indexed compactly so the result is a standalone mesh (in anchor-local space).
    private func obstacleGeometry(from geometry: ARMeshGeometry) -> MeshData? {
        let source = geometry.vertices
        let vertexBuffer = source.buffer.contents()

        func vertex(_ index: Int) -> SIMD3<Float> {
            vertexBuffer
                .advanced(by: source.offset + source.stride * index)
                .assumingMemoryBound(to: SIMD3<Float>.self)
                .pointee
        }

        let faces = geometry.faces
        let cornersPerFace = faces.indexCountPerPrimitive
        let faceBuffer = faces.buffer.contents()
        let bytesPerIndex = faces.bytesPerIndex

        func faceCornerIndex(face: Int, corner: Int) -> Int {
            let ptr = faceBuffer.advanced(by: (face * cornersPerFace + corner) * bytesPerIndex)
            if bytesPerIndex == 2 {
                return Int(ptr.assumingMemoryBound(to: UInt16.self).pointee)
            }
            return Int(ptr.assumingMemoryBound(to: UInt32.self).pointee)
        }

        let classification = geometry.classification
        let classBuffer = classification?.buffer.contents()
        let classStride = classification?.stride ?? 0
        let classOffset = classification?.offset ?? 0

        func isFloor(face: Int) -> Bool {
            guard let classBuffer else { return false }
            let raw = classBuffer
                .advanced(by: classOffset + classStride * face)
                .assumingMemoryBound(to: UInt8.self)
                .pointee
            return ARMeshClassification(rawValue: Int(raw)) == .floor
        }

        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var remap: [Int: UInt32] = [:]

        for face in 0..<faces.count {
            if isFloor(face: face) { continue } // land is provided by planes
            for corner in 0..<cornersPerFace {
                let original = faceCornerIndex(face: face, corner: corner)
                if let existing = remap[original] {
                    indices.append(existing)
                } else {
                    let newIndex = UInt32(positions.count)
                    remap[original] = newIndex
                    positions.append(vertex(original))
                    indices.append(newIndex)
                }
            }
        }

        return positions.isEmpty ? nil : MeshData(positions: positions, indices: indices)
    }

    private func meshDescriptor(from data: MeshData) -> MeshDescriptor {
        var descriptor = MeshDescriptor(name: "obstacle")
        descriptor.positions = MeshBuffer(data.positions)
        descriptor.primitives = .triangles(data.indices)
        return descriptor
    }
}

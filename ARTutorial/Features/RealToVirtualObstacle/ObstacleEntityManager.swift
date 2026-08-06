//
//  ObstacleEntityManager.swift
//  Hijauin
//
//  Created by Reynard Amadeus  on 06/08/26.
//

//  Turns `DetectedObstacle` boxes into RealityKit entities with static
//  collision + physics, and reconciles them across detection passes so
//  boxes are updated in place instead of flickering / being recreated.
//
//  Each obstacle is a box-shaped static physics body. The robot (a dynamic
//  body elsewhere in your app) then collides and navigates using RealityKit's
//  built-in physics — no manual movement math.
//
 
import RealityKit
import simd
import Foundation

@MainActor
final class ObstacleEntityManager {
 
    /// Parent entity all obstacles are attached to (e.g. an AnchorEntity on the table).
    private let root: Entity
 
    /// Live obstacle entities keyed by a stable id we assign on first sight.
    private var entities: [UUID: ModelEntity] = [:]
 
    /// How close (meters) a new detection must be to an existing obstacle's
    /// center to be treated as the *same* object rather than a new one.
    var matchDistance: Float = 0.06
 
    /// Set false to hide the debug boxes but keep collision active.
    var showsDebugMesh: Bool = true
 
    init(root: Entity) {
        self.root = root
    }
 
    /// Reconcile the scene with the latest detections.
    func update(with detections: [RealObstacle]) {
        var unmatched = Set(entities.keys)
 
        for detection in detections {
            if let id = nearestExisting(to: detection.center, within: matchDistance) {
                // Same object seen again — update its shape/position in place.
                updateEntity(entities[id]!, to: detection)
                unmatched.remove(id)
            } else {
                // New object.
                let entity = makeEntity(for: detection)
                entities[detection.id] = entity
                root.addChild(entity)
            }
        }
 
        // Anything not matched this pass has disappeared — remove it.
        for id in unmatched {
            entities[id]?.removeFromParent()
            entities[id] = nil
        }
    }
 
    /// Remove every obstacle (e.g. when the user re-scans).
    func reset() {
        for (_, e) in entities { e.removeFromParent() }
        entities.removeAll()
    }
 
    // MARK: Entity construction
 
    private func makeEntity(for o: RealObstacle) -> ModelEntity {
        let mesh = MeshResource.generateBox(size: o.extents)
        let material = SimpleMaterial(
            color: .init(red: 0.1, green: 0.6, blue: 1.0, alpha: showsDebugMesh ? 0.35 : 0.0),
            isMetallic: false
        )
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = o.center
 
        let shape = ShapeResource.generateBox(size: o.extents)
        entity.collision = CollisionComponent(shapes: [shape])
        entity.physicsBody = PhysicsBodyComponent(
            shapes: [shape],
            mass: 0,
            mode: .static          // obstacles don't move; the robot reacts to them
        )
        return entity
    }
 
    private func updateEntity(_ entity: ModelEntity, to o: RealObstacle) {
        entity.position = o.center
        entity.model?.mesh = MeshResource.generateBox(size: o.extents)
        let shape = ShapeResource.generateBox(size: o.extents)
        entity.collision = CollisionComponent(shapes: [shape])
        entity.physicsBody = PhysicsBodyComponent(shapes: [shape], mass: 0, mode: .static)
    }
 
    // MARK: Matching
 
    private func nearestExisting(to point: SIMD3<Float>, within radius: Float) -> UUID? {
        var best: UUID?
        var bestDist = radius
        for (id, entity) in entities {
            let d = simd_distance(entity.position, point)
            if d < bestDist { bestDist = d; best = id }
        }
        return best
    }
}

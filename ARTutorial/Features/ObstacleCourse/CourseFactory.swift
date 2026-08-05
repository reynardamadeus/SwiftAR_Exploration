//
//  CourseFactory.swift
//  ARTutorial
//
//  Assembles the full obstacle course: a start pad, the scanned obstacles, a finish
//  deck, and the config-driven vehicle — all under one root, ready to attach to an
//  `AnchorEntity`. Physics is the same static/dynamic mix as `PhysicsSceneFactory`;
//  the anchor still needs a `PhysicsSimulationComponent` (see coordinator).
//

import RealityKit
import UIKit

/// The assembled course plus handles the coordinator needs.
struct ObstacleCourse {
    /// Root holding pad + obstacles + finish + vehicle.
    let root: Entity
    /// The dynamic vehicle (carries `PhysicsRobotComponent` + `CourseRunComponent`).
    let vehicle: Entity
    /// World-space finish point the vehicle drives toward.
    let finishPoint: SIMD3<Float>
}

enum CourseFactory {

    private static let padMaterial = PhysicsMaterialResource.generate(friction: 0.9, restitution: 0.0)

    /// Builds a course laid out along local +X: start pad at one end, finish at the
    /// other, obstacles positioned by their scan footprints in between.
    ///
    /// - Parameters:
    ///   - obstacles: confirmed detections (world centres are treated as *local* to
    ///     the course root here; the coordinator anchors the root at the table).
    ///   - config: the child's current vehicle design.
    ///   - length: local distance from start to finish (metres).
    static func makeCourse(obstacles: [DetectedObstacle],
                           config: RobotConfig,
                           length: Float = 0.6) -> ObstacleCourse {
        let root = Entity()

        // Ground strip the whole course sits on.
        let ground = staticBox(size: [length + 0.1, 0.02, 0.3],
                               color: UIColor.systemGray4.withAlphaComponent(0.9))
        ground.position = [length / 2, -0.01, 0]
        root.addChild(ground)

        // Start pad (local origin) and finish deck (far +X end).
        let startPad = staticBox(size: [0.1, 0.02, 0.2], color: .systemGreen)
        startPad.position = [0, 0.001, 0]
        root.addChild(startPad)

        let finishPoint = SIMD3<Float>(length, 0.02, 0)
        root.addChild(makeFinish(at: finishPoint))

        // Obstacles between start and finish.
        for detection in obstacles {
            root.addChild(ObstacleFactory.makeObstacle(from: detection))
        }

        // Vehicle at the start, lifted slightly so gravity settles it onto the pad.
        let vehicle = VehicleFactory.makeVehicle(from: config)
        vehicle.position = [0, 0.05, 0]
        vehicle.components.set(CourseRunComponent(finishPoint: finishPoint))
        // Drive it toward the finish + record spawn for fall recovery.
        if var rc = vehicle.components[PhysicsRobotComponent.self] {
            rc.targetPosition = finishPoint
            rc.startPosition = vehicle.position
            vehicle.components.set(rc)
        }
        root.addChild(vehicle)

        return ObstacleCourse(root: root, vehicle: vehicle, finishPoint: finishPoint)
    }

    /// Finish deck: a static pad that also acts as a trigger for a crisp win event.
    private static func makeFinish(at position: SIMD3<Float>) -> Entity {
        let deck = staticBox(size: [0.1, 0.02, 0.2],
                             color: UIColor.systemYellow.withAlphaComponent(0.95))
        deck.position = position
        deck.components.set(FinishLineComponent())
        return deck
    }

    private static func staticBox(size: SIMD3<Float>, color: UIColor) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateBox(size: size),
            materials: [SimpleMaterial(color: color, isMetallic: false)]
        )
        let shape = ShapeResource.generateBox(size: size)
        entity.components.set(CollisionComponent(shapes: [shape]))
        entity.components.set(PhysicsBodyComponent(
            shapes: [shape], mass: 1, material: padMaterial, mode: .static
        ))
        return entity
    }
}

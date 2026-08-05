//
//  ObstacleFactory.swift
//  ARTutorial
//
//  Turns a `DetectedObstacle` into a clean RealityKit prop, following the exact
//  static-body pattern established in `PhysicsSceneFactory` (matching visual +
//  collision geometry, `PhysicsBodyComponent(mode: .static)`). Every prop carries an
//  `ObstacleMarkerComponent` so the evaluation + feedback systems know what it is.
//
//  Note on API: RealityKit has ONE physics body type switched by `mode`; static
//  props still require a mass in the initializer even though it's ignored.
//

import RealityKit
import UIKit

enum ObstacleFactory {

    private static let surfaceMaterial = PhysicsMaterialResource.generate(friction: 0.85, restitution: 0.0)

    /// Builds a positioned, physics-ready prop for one detected region.
    /// The returned entity is placed at `detection.worldCenter` in world space; add
    /// it to the course anchor.
    static func makeObstacle(from detection: DetectedObstacle) -> Entity {
        let entity: Entity
        switch detection.kind {
        case .rock:   entity = makeRock(detection)
        case .ramp:   entity = makeRamp(detection)
        case .bridge: entity = makeBridge(detection)
        case .tunnel: entity = makeTunnel(detection)
        }
        entity.position = detection.worldCenter
        entity.orientation = simd_quatf(angle: detection.yaw, axis: [0, 1, 0])
        entity.components.set(ObstacleMarkerComponent(kind: detection.kind))
        return entity
    }

    // MARK: - Kinds

    /// Solid blocker. Low rocks are climbable by the step-over logic; tall ones block.
    /// Wrapped in a parent whose origin is at ground level so the caller can set the
    /// world position without clobbering the box's vertical lift.
    private static func makeRock(_ d: DetectedObstacle) -> Entity {
        let parent = Entity()
        let size = SIMD3<Float>(d.footprint.x, d.estimatedHeight, d.footprint.y)
        parent.addChild(staticBox(size: size,
                                  color: UIColor.systemGray.withAlphaComponent(0.95),
                                  yOffset: d.estimatedHeight / 2))
        return parent
    }

    /// Tilted static box the vehicle climbs. Angle is capped so impulse locomotion
    /// stays stable on it. The tilt lives on the child so the parent's yaw (applied by
    /// the caller) composes with it correctly.
    private static func makeRamp(_ d: DetectedObstacle) -> Entity {
        let parent = Entity()
        let thickness: Float = 0.02
        let run = d.footprint.x
        let rise = min(d.estimatedHeight, run * 0.6) // cap slope
        let box = staticBox(size: [run, thickness, d.footprint.y],
                            color: UIColor.systemOrange.withAlphaComponent(0.95),
                            yOffset: rise / 2)
        box.orientation = simd_quatf(angle: atan2(rise, run), axis: [0, 0, 1])
        parent.addChild(box)
        return parent
    }

    /// Raised deck on two piers, leaving a gap underneath.
    private static func makeBridge(_ d: DetectedObstacle) -> Entity {
        let parent = Entity()
        let deckThickness: Float = 0.02
        let clearance = d.kind.openingHeight ?? 0.06
        let deck = staticBox(size: [d.footprint.x, deckThickness, d.footprint.y],
                             color: UIColor.systemBrown.withAlphaComponent(0.95),
                             yOffset: clearance + deckThickness / 2)
        let pierSize = SIMD3<Float>(0.02, clearance, d.footprint.y)
        let leftPier = staticBox(size: pierSize, color: .systemBrown, yOffset: clearance / 2)
        leftPier.position.x = -d.footprint.x / 2 + 0.01
        let rightPier = staticBox(size: pierSize, color: .systemBrown, yOffset: clearance / 2)
        rightPier.position.x = d.footprint.x / 2 - 0.01
        parent.addChild(deck); parent.addChild(leftPier); parent.addChild(rightPier)
        return parent
    }

    /// Portal: two walls + a lintel. The vehicle must be shorter than the opening.
    private static func makeTunnel(_ d: DetectedObstacle) -> Entity {
        let parent = Entity()
        let opening = d.kind.openingHeight ?? 0.075
        let wallThickness: Float = 0.02
        let wallSize = SIMD3<Float>(wallThickness, opening, d.footprint.y)
        let left = staticBox(size: wallSize, color: UIColor.systemPurple.withAlphaComponent(0.95),
                             yOffset: opening / 2)
        left.position.x = -d.footprint.x / 2 + wallThickness / 2
        let right = staticBox(size: wallSize, color: UIColor.systemPurple.withAlphaComponent(0.95),
                              yOffset: opening / 2)
        right.position.x = d.footprint.x / 2 - wallThickness / 2
        let lintelThickness: Float = 0.02
        let lintel = staticBox(size: [d.footprint.x, lintelThickness, d.footprint.y],
                               color: UIColor.systemPurple.withAlphaComponent(0.95),
                               yOffset: opening + lintelThickness / 2)
        parent.addChild(left); parent.addChild(right); parent.addChild(lintel)
        return parent
    }

    // MARK: - Shared builder (mirrors PhysicsSceneFactory.makeStaticBox)

    /// A static box whose *top or centre* sits at `yOffset` above the prop origin.
    private static func staticBox(size: SIMD3<Float>, color: UIColor, yOffset: Float) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateBox(size: size),
            materials: [SimpleMaterial(color: color, isMetallic: false)]
        )
        entity.position.y = yOffset
        let shape = ShapeResource.generateBox(size: size)
        entity.components.set(CollisionComponent(shapes: [shape]))
        entity.components.set(PhysicsBodyComponent(
            shapes: [shape],
            mass: 1,               // ignored for static bodies, required by init
            material: surfaceMaterial,
            mode: .static
        ))
        return entity
    }
}

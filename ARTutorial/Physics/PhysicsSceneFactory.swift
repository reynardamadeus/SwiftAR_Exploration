//
//  PhysicsSceneFactory.swift
//  ARTutorial
//
//  Builds the physics playground: ground, walls, a ramp, a raised platform,
//  pushable boxes, and the robot itself. Everything the robot interacts with is a
//  RealityKit physics body:
//
//    • Ground / walls / ramp / platform → PhysicsBodyComponent(mode: .static)
//    • Pushable boxes / robot           → PhysicsBodyComponent(mode: .dynamic)
//
//  The five PoC behaviours all emerge from this setup without scripting motion:
//    Climb    – drive up the ramp's sloped static geometry (friction + normal force)
//    Descend  – drive back down the same ramp; gravity keeps contact
//    Push     – dynamic robot vs. low-mass dynamic boxes
//    Fall     – walk off the open platform edge; gravity takes over
//    Collision– static walls + correct collision shapes stop any pass-through
//
//  Note on API: RealityKit has ONE physics body type, `PhysicsBodyComponent`,
//  switched via `mode` (.static / .dynamic / .kinematic) — there is no separate
//  StaticPhysicsBodyComponent / DynamicPhysicsBodyComponent.
//

import RealityKit
import UIKit

/// The assembled playground plus a handle to the robot the coordinator steers.
struct PhysicsPlayground {
    /// Root entity holding the whole playground. Owns the physics simulation.
    let root: Entity
    /// The dynamic robot entity (carries `PhysicsRobotComponent`).
    let robot: Entity
    /// Entities that count as walkable/targetable surfaces (for tap raycasts).
    let surfaces: [Entity]
}

enum PhysicsSceneFactory {

    // MARK: - Tunables (world-scale metres). Kept small for a tabletop feel.

    private static let groundSize     = SIMD3<Float>(0.60, 0.02, 0.60)
    private static let platformHeight: Float = 0.08
    private static let platformSize   = SIMD3<Float>(0.20, 0.02, 0.26)
    private static let rampSize       = SIMD3<Float>(0.20, 0.02, 0.22)
    private static let wallHeight: Float = 0.07
    private static let wallThickness: Float = 0.02
    private static let robotHeight: Float = 0.08

    /// Tuning note: at this small scale the default Earth gravity (-9.81 m/s²) makes
    /// falls look quite snappy. If you build for iOS 18+ you can soften it by adding a
    /// `PhysicsSimulationComponent` with a reduced gravity vector to `root`; it's left
    /// out here so the PoC compiles against older SDKs and uses the default simulation.

    // Physics materials.
    private static let surfaceMaterial = PhysicsMaterialResource.generate(friction: 0.85, restitution: 0.0)
    private static let robotMaterial   = PhysicsMaterialResource.generate(friction: 0.65, restitution: 0.0)
    private static let boxMaterial     = PhysicsMaterialResource.generate(friction: 0.55, restitution: 0.0)

    // MARK: - Assembly

    /// Builds the full playground. Attach `.root` to an `AnchorEntity` to place it.
    static func makePlayground() -> PhysicsPlayground {
        let root = Entity()
        var surfaces: [Entity] = []

        // Ground — top surface at y = 0.
        let ground = makeStaticBox(
            size: groundSize,
            color: UIColor.systemGray4.withAlphaComponent(0.9),
            position: [0, -groundSize.y / 2, 0]
        )
        root.addChild(ground)
        surfaces.append(ground)

        // Raised platform on the +X side, top at y = platformHeight.
        let platformCenterX: Float = 0.19
        let platform = makeStaticBox(
            size: platformSize,
            color: UIColor.systemTeal.withAlphaComponent(0.9),
            position: [platformCenterX, platformHeight - platformSize.y / 2, 0]
        )
        root.addChild(platform)
        surfaces.append(platform)

        // Ramp bridging ground (y=0) up to the platform top (y=platformHeight).
        // A static box tilted about +Z so its top face rises toward +X.
        let rampAngle = atan2(platformHeight, rampSize.x) // slope from run & rise
        let ramp = makeStaticBox(
            size: rampSize,
            color: UIColor.systemOrange.withAlphaComponent(0.9),
            position: [0.0, platformHeight / 2, 0]
        )
        ramp.orientation = simd_quatf(angle: rampAngle, axis: [0, 0, 1])
        root.addChild(ramp)
        surfaces.append(ramp)

        // Two perimeter walls (back + left) to demonstrate collision. The platform's
        // far +X edge and the front are deliberately left open so the robot can fall.
        let backWall = makeStaticBox(
            size: [groundSize.x, wallHeight, wallThickness],
            color: UIColor.systemGray2.withAlphaComponent(0.6),
            position: [0, wallHeight / 2, -groundSize.z / 2 + wallThickness / 2]
        )
        let leftWall = makeStaticBox(
            size: [wallThickness, wallHeight, groundSize.z],
            color: UIColor.systemGray2.withAlphaComponent(0.6),
            position: [-groundSize.x / 2 + wallThickness / 2, wallHeight / 2, 0]
        )
        root.addChild(backWall)
        root.addChild(leftWall)

        // Step-over demo: a low step (below 1/4 of the 8 cm robot → climbable) and a
        // taller block (above the threshold → blocks). Robot height is `robotHeight`,
        // so the climbable ceiling is robotHeight * 0.25 ≈ 0.02 m.
        let lowStep = makeStaticBox(
            size: [0.07, 0.018, 0.07],
            color: UIColor.systemGreen.withAlphaComponent(0.9),
            position: [-0.12, 0.009, -0.02]
        )
        let tallBlock = makeStaticBox(
            size: [0.06, 0.05, 0.06],
            color: UIColor.systemRed.withAlphaComponent(0.9),
            position: [-0.12, 0.025, 0.18]
        )
        root.addChild(lowStep)
        root.addChild(tallBlock)
        surfaces.append(lowStep)
        surfaces.append(tallBlock)

        // Pushable boxes — low-mass dynamic bodies in the robot's likely path.
        let boxA = makeDynamicBox(edge: 0.04, color: .systemPink, position: [-0.05, 0.05, 0.10], mass: 0.05)
        let boxB = makeDynamicBox(edge: 0.04, color: .systemIndigo, position: [-0.02, 0.05, -0.06], mass: 0.05)
        root.addChild(boxA)
        root.addChild(boxB)

        // Robot — dynamic body, spawned above the ground so it settles via gravity.
        let robot = makeRobot()
        robot.position = [-0.22, 0.06, 0.16]
        root.addChild(robot)

        return PhysicsPlayground(root: root, robot: robot, surfaces: surfaces)
    }

    // MARK: - Builders

    /// A static, immovable box with matching visual + collision geometry.
    private static func makeStaticBox(size: SIMD3<Float>, color: UIColor, position: SIMD3<Float>) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateBox(size: size),
            materials: [SimpleMaterial(color: color, isMetallic: false)]
        )
        entity.position = position
        let shape = ShapeResource.generateBox(size: size)
        entity.components.set(CollisionComponent(shapes: [shape]))
        // Mass is irrelevant for a static body but the initializer requires one.
        entity.components.set(PhysicsBodyComponent(
            shapes: [shape],
            mass: 1,
            material: surfaceMaterial,
            mode: .static
        ))
        return entity
    }

    /// A movable, physics-simulated box the robot can push.
    private static func makeDynamicBox(edge: Float, color: UIColor, position: SIMD3<Float>, mass: Float) -> ModelEntity {
        let size = SIMD3<Float>(repeating: edge)
        let entity = ModelEntity(
            mesh: .generateBox(size: size),
            materials: [SimpleMaterial(color: color, isMetallic: false)]
        )
        entity.position = position
        let shape = ShapeResource.generateBox(size: size)
        entity.components.set(CollisionComponent(shapes: [shape]))
        entity.components.set(PhysicsBodyComponent(
            shapes: [shape],
            mass: mass,
            material: boxMaterial,
            mode: .dynamic
        ))
        entity.components.set(PhysicsMotionComponent())
        return entity
    }

    /// Builds the robot as a physics container that holds the visual model.
    /// Decoupling the container (scale 1) from the scaled visual keeps the
    /// collision-box maths in clean world units. Exposed so real-world scan mode
    /// can spawn the same robot without the synthetic playground.
    static func makeRobot() -> Entity {
        let container = Entity()

        // Size of the robot's collision box (world metres). Slightly slimmer than
        // the mesh for a stable footprint; height matches `robotHeight`.
        var bodySize = SIMD3<Float>(0.05, robotHeight, 0.05)

        if let visual = try? Entity.loadModel(named: "robot") {
            // Fit the model to `robotHeight` and stand it on the container origin.
            let bounds = visual.visualBounds(relativeTo: visual)
            let extents = bounds.extents
            let scaleFactor = extents.y > 0 ? robotHeight / extents.y : 1
            visual.scale = SIMD3<Float>(repeating: scaleFactor)

            let scaledCenter = bounds.center * scaleFactor
            let scaledExtents = extents * scaleFactor
            // Recentre in X/Z and drop feet to y = 0.
            visual.position = [-scaledCenter.x, -bounds.min.y * scaleFactor, -scaledCenter.z]
            container.addChild(visual)

            bodySize = SIMD3<Float>(scaledExtents.x * 0.8, scaledExtents.y, scaledExtents.z * 0.8)
        } else {
            // Fallback box if the model fails to load.
            let placeholder = ModelEntity(
                mesh: .generateBox(size: bodySize),
                materials: [SimpleMaterial(color: .systemRed, isMetallic: false)]
            )
            placeholder.position = [0, bodySize.y / 2, 0]
            container.addChild(placeholder)
        }

        // Collision box: base sitting on the container origin (offset up by half height).
        let shape = ShapeResource.generateBox(size: bodySize)
            .offsetBy(translation: [0, bodySize.y / 2, 0])
        container.components.set(CollisionComponent(shapes: [shape]))
        container.components.set(PhysicsBodyComponent(
            shapes: [shape],
            mass: 0.4,
            material: robotMaterial,
            mode: .dynamic
        ))
        container.components.set(PhysicsMotionComponent())
        container.components.set(PhysicsRobotComponent(
            bodyHeight: bodySize.y,
            bodyRadius: min(bodySize.x, bodySize.z) * 0.5
        ))

        return container
    }
}

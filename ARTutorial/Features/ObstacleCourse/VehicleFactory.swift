//
//  VehicleFactory.swift
//  ARTutorial
//
//  Bridges the *design* (`RobotConfig` from the editor) to a *physics vehicle* for
//  a course run. RealityKit has no wheel-collider / drivetrain, so — deliberately,
//  for the MVP — the vehicle is a single dynamic body whose behaviour encodes the
//  child's design choices:
//
//    • Tire type   → the body's friction material (grip)
//    • Wheel scale → ground clearance (how high the chassis rides)
//    • Body L×W×H  → collision box + stability + the tunnel-height test
//
//  This is enough to *teach* grip, clearance and height without simulating a real
//  drivetrain, and it reuses `RobotEntity` + `PhysicsRobotComponent` so the existing
//  `RobotControlSystem` drives it unchanged.
//

import RealityKit
import UIKit

enum VehicleFactory {

    /// Friction per tire type. `smooth` is slippery (racing/city), `offroad` grips
    /// hard, `heavy` sits in between. Add a `snow` case to `RobotConfig.WheelType`
    /// and one line here to extend the set.
    static func friction(for tire: RobotConfig.WheelType) -> Float {
        switch tire {
        case .none:    return 0.4
        case .smooth:  return 0.45
        case .heavy:   return 0.8
        case .offroad: return 0.95
        }
    }

    /// Ground clearance (metres) from the wheel-size slider: bigger wheels ride
    /// higher, letting the chassis clear low obstacles without scraping.
    static func clearance(for wheelScale: Float) -> Float {
        let base: Float = 0.015
        return base + max(0, wheelScale) * 0.12
    }

    /// The dominant tire on the vehicle (majority of installed wheels), used to pick
    /// the single body friction material. A pragmatic simplification of four
    /// independent tires into one grip value.
    static func dominantTire(_ config: RobotConfig) -> RobotConfig.WheelType {
        let tires = WheelSlot.allCases.map { config[$0].type }.filter { $0 != .none }
        guard !tires.isEmpty else { return .smooth }
        let counts = Dictionary(grouping: tires, by: { $0 }).mapValues(\.count)
        return counts.max(by: { $0.value < $1.value })!.key
    }

    /// Builds a config-driven physics vehicle centred on its own origin (feet at
    /// y = 0). Add it to the course anchor and set its `startPosition`.
    static func makeVehicle(from config: RobotConfig) -> Entity {
        let container = RobotEntity()

        // Convert editor-scale body dimensions to world metres (toy scale).
        let s = RobotGeometry.arScale
        let bodySize = SIMD3<Float>(
            config.bodySize.length * s,
            config.bodySize.height * s,
            config.bodySize.width * s
        )
        let ride = clearance(for: config.wheelScale)

        // Visual chassis (also carries the collision box). Lifted by `ride` so the
        // gap under it is the wheels' ground clearance.
        let chassis = ModelEntity(
            mesh: .generateBox(size: bodySize),
            materials: [SimpleMaterial(color: UIColor(red: 0.25, green: 0.6, blue: 0.95, alpha: 1),
                                       isMetallic: false)]
        )
        chassis.position.y = ride + bodySize.y / 2
        container.addChild(chassis)

        // Simple wheel visuals at the four corners (cosmetic; physics is body-level).
        addWheels(to: container, config: config, bodySize: bodySize, ride: ride)

        // Collision box spans clearance → top, so the body can scrape a tall obstacle
        // but a well-lifted chassis clears a low one.
        let collisionHeight = ride + bodySize.y
        let shape = ShapeResource.generateBox(size: [bodySize.x, collisionHeight, bodySize.z])
            .offsetBy(translation: [0, collisionHeight / 2, 0])
        container.components.set(CollisionComponent(shapes: [shape]))

        let tire = dominantTire(config)
        container.components.set(PhysicsBodyComponent(
            shapes: [shape],
            mass: max(0.1, config.bodyMass * 0.05),
            material: .generate(friction: friction(for: tire), restitution: 0.0),
            mode: .dynamic
        ))
        container.components.set(PhysicsMotionComponent())

        // Locomotion metrics for RobotControlSystem. bodyHeight = full collision
        // height so step-over + the tunnel test reason about the real silhouette.
        container.components.set(PhysicsRobotComponent(
            bodyHeight: collisionHeight,
            bodyRadius: min(bodySize.x, bodySize.z) * 0.5
        ))

        return container
    }

    private static func addWheels(to container: Entity, config: RobotConfig,
                                  bodySize: SIMD3<Float>, ride: Float) {
        let hx = bodySize.x / 2, hz = bodySize.z / 2
        let scale = max(0.02, config.wheelScale)
        for slot in WheelSlot.allCases {
            let wheel = WheelFactory.makeWheel(for: config[slot].type, scaleMultiplier: scale)
            let signX: Float = (slot == .frontLeft || slot == .frontRight) ? 1 : -1
            let signZ: Float = (slot == .frontRight || slot == .rearRight) ? 1 : -1
            wheel.position = [signX * hx, ride * 0.5, signZ * hz]
            container.addChild(wheel)
        }
    }
}

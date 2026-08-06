//
//  Mission1VehicleSystem.swift
//  ARTutorial
//
//  Drives the Mission 1 raycast-suspension vehicle. Each frame, for every wheel:
//
//    1. Cast a ray straight down from the wheel's attach point.
//    2. If it hits ground within reach, push the chassis up with a spring-damper
//       (suspension) applied *at that corner* — four corner pushes make the car
//       self-level and pitch to follow the ramp instead of toppling.
//    3. Apply a forward drive force and cancel sideways slip (grip) at the contact.
//    4. Slide the visual wheel to the contact and spin it by the travel speed.
//
//  Forces are applied as impulses (force × dt) via `applyImpulse(_:at:relativeTo:)`,
//  so all torque/levelling emerges from the offset contact points — no scripted
//  orientation. Register once with `bootstrap()`.
//

import RealityKit
import Foundation

private typealias PhysicsDrivable = Entity & HasPhysicsBody & HasPhysicsMotion

final class Mission1VehicleSystem: System {

    private static let query = EntityQuery(where: .has(Mission1VehicleComponent.self)
                                           && .has(PhysicsMotionComponent.self))

    required init(scene: Scene) {}

    private static var didBootstrap = false
    static func bootstrap() {
        guard !didBootstrap else { return }
        Mission1VehicleComponent.registerComponent()
        Mission1VehicleSystem.registerSystem()
        didBootstrap = true
    }

    func update(context: SceneUpdateContext) {
        let dt = Float(context.deltaTime)
        guard dt > 0 else { return }
        let scene = context.scene

        for entity in scene.performQuery(Self.query) {
            guard
                var vc = entity.components[Mission1VehicleComponent.self],
                let motion = entity.components[PhysicsMotionComponent.self],
                let body = entity as? PhysicsDrivable
            else { continue }

            let mass = entity.components[PhysicsBodyComponent.self]?.massProperties.mass ?? 0.5
            let com = entity.position(relativeTo: nil)
            let up = normalized(entity.orientation.act(SIMD3<Float>(0, 1, 0)), fallback: [0, 1, 0])
            let linVel = motion.linearVelocity
            let angVel = motion.angularVelocity

            // Drive direction (horizontal) toward the target.
            var driveDir = SIMD3<Float>(0, 0, 0)
            if let target = vc.targetPosition {
                let to = SIMD3<Float>(target.x - com.x, 0, target.z - com.z)
                let d = simd_length(to)
                if d > vc.arriveThreshold { driveDir = to / d } else { vc.targetPosition = nil }
            }

            // Heading + side axis for grip (use nose when idle).
            let nose = normalized(entity.orientation.act(SIMD3<Float>(1, 0, 0)), fallback: [1, 0, 0])
            let heading = simd_length(driveDir) > 0.001 ? driveDir : nose
            let side = normalized(simd_cross(up, heading), fallback: [0, 0, 1])

            let reach = vc.restLength + vc.wheelRadius
            let perWheelMass = mass / Float(max(1, vc.wheels.count))

            for wheel in vc.wheels {
                let attachWorld = entity.convert(position: wheel.attach, to: nil)
                let hits = scene.raycast(origin: attachWorld, direction: -up,
                                         length: reach, query: .all)
                let hit = hits.first { $0.entity.id != entity.id
                                       && !$0.entity.isDescendant(of: entity) }

                if let hit = hit {
                    let compression = max(0, reach - hit.distance)

                    // Velocity of this corner (linear + rotational).
                    let r = attachWorld - com
                    let pointVel = linVel + simd_cross(angVel, r)

                    // Suspension: spring pushes out along `up`, damper resists motion
                    // along `up`. Push-only (never pulls the chassis down).
                    let springN = vc.stiffness * compression - vc.damping * simd_dot(pointVel, up)
                    if springN > 0 {
                        body.applyImpulse(up * (springN * dt), at: attachWorld, relativeTo: nil)
                    }

                    // Drive: forward force along the ground plane, capped at maxSpeed.
                    if simd_length(driveDir) > 0.001 {
                        let n = normalized(hit.normal, fallback: up)
                        let onGround = normalized(driveDir - n * simd_dot(driveDir, n),
                                                  fallback: driveDir)
                        if simd_dot(linVel, onGround) < vc.maxSpeed {
                            body.applyImpulse(onGround * (vc.driveForce * dt),
                                              at: attachWorld, relativeTo: nil)
                        }
                    }

                    // Grip: cancel sideways slip at the contact.
                    let lateral = simd_dot(pointVel, side)
                    body.applyImpulse(side * (-lateral * perWheelMass * vc.grip),
                                      at: attachWorld, relativeTo: nil)

                    // Visual: drop the wheel to the contact.
                    let drop = max(0, hit.distance - vc.wheelRadius)
                    wheel.visual.position = [wheel.attach.x, wheel.attach.y - drop, wheel.attach.z]
                } else {
                    // Airborne: hang the wheel at full extension.
                    wheel.visual.position = [wheel.attach.x, wheel.attach.y - vc.restLength, wheel.attach.z]
                }
            }

            // Spin the wheels by forward speed (visual only). The hub's children carry
            // the axle alignment (axle along Z), so spinning the hub about Z rolls them.
            let speed = simd_length(SIMD3<Float>(linVel.x, 0, linVel.z))
            vc.spinAngle += (speed / max(0.001, vc.wheelRadius)) * dt
            let spin = simd_quatf(angle: vc.spinAngle, axis: [0, 0, 1])
            for wheel in vc.wheels { wheel.visual.orientation = spin }

            // Off-map fall recovery (only position write, as a safeguard).
            if let start = vc.startPosition, com.y < start.y - vc.fallRecoveryDepth {
                entity.setPosition(start, relativeTo: nil)
                entity.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
                if var m = entity.components[PhysicsMotionComponent.self] {
                    m.linearVelocity = .zero
                    m.angularVelocity = .zero
                    entity.components.set(m)
                }
                vc.targetPosition = nil
            }

            entity.components.set(vc)
        }
    }

    /// Normalises a vector, returning `fallback` when it's too short to normalise.
    private func normalized(_ v: SIMD3<Float>, fallback: SIMD3<Float>) -> SIMD3<Float> {
        let len = simd_length(v)
        return len > 0.0001 ? v / len : fallback
    }
}

private extension Entity {
    /// Whether this entity is anywhere below `ancestor` in the hierarchy.
    func isDescendant(of ancestor: Entity) -> Bool {
        var node = parent
        while let current = node {
            if current.id == ancestor.id { return true }
            node = current.parent
        }
        return false
    }
}

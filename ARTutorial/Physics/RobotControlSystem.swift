//
//  RobotControlSystem.swift
//  ARTutorial
//
//  Drives the robot toward its tap target using physics, never by scripting Y to
//  locomote. Locomotion is applied as *impulses* on a dynamic body rather than by
//  writing `linearVelocity` directly: a settled dynamic body goes to sleep, and a
//  sleeping body ignores velocity writes — so a velocity-only robot never starts
//  moving. Each frame we apply the impulse needed to reach the target horizontal
//  velocity, which both wakes the body and moves it.
//
//   • Step-over  – a low obstacle (top ≤ 1/4 of the robot's height) gets a small
//                  upward impulse so the robot mounts it; taller obstacles are left
//                  to block via collision.
//   • Fall       – while airborne the robot keeps its momentum and lets gravity
//                  arc it down naturally (no forced horizontal drive). If it falls
//                  completely off the mapped world it is respawned at its start.
//
//  All vertical motion is produced by the physics solver or by *impulse* nudges;
//  the only place a position is written is the off-map respawn safeguard.
//
//  Reusable RealityKit `System`; register once with `registerSystem()`.
//

import RealityKit
import Foundation

/// Anything the system can push around: has a physics body (for impulses) and a
/// motion component (to read current velocity).
private typealias PhysicsDrivable = Entity & HasPhysicsBody & HasPhysicsMotion

final class RobotControlSystem: System {

    private static let query = EntityQuery(where: .has(PhysicsRobotComponent.self)
                                           && .has(PhysicsMotionComponent.self))

    /// Smallest rise we bother treating as a step (ignores surface noise / the
    /// floor the robot is already standing on).
    private static let minStepHeight: Float = 0.004

    required init(scene: Scene) {}

    /// Registers the robot component + this system exactly once per process.
    /// Safe to call from every screen that spawns a robot.
    private static var didBootstrap = false
    static func bootstrap() {
        guard !didBootstrap else { return }
        PhysicsRobotComponent.registerComponent()
        RobotControlSystem.registerSystem()
        didBootstrap = true
    }

    // Temporary diagnostics: throttled so the console stays readable.
    private static var frame: UInt64 = 0

    func update(context: SceneUpdateContext) {
        let scene = context.scene
        Self.frame &+= 1
        let shouldLog = Self.frame % 30 == 0   // ~ twice per second

        var matched = 0
        for entity in scene.performQuery(Self.query) {
            matched += 1
            guard
                var robot = entity.components[PhysicsRobotComponent.self],
                let motion = entity.components[PhysicsMotionComponent.self]
            else { continue }

            let castable = entity is PhysicsDrivable
            guard let body = entity as? PhysicsDrivable else {
                if shouldLog { print("[Robot] ⚠️ entity is NOT PhysicsDrivable (cast failed) — can't apply impulses") }
                continue
            }

            let mass = entity.components[PhysicsBodyComponent.self]?.massProperties.mass ?? 1
            let velocity = motion.linearVelocity
            let feet = entity.position(relativeTo: nil)
            let grounded = isGrounded(entity: entity, feet: feet, robot: robot, scene: scene)

            if shouldLog {
                let target = robot.targetPosition.map { String(format: "(%.2f,%.2f)", $0.x, $0.z) } ?? "nil"
                print(String(format: "[Robot] grounded=%@ y=%.3f target=%@ vel=(%.2f,%.2f,%.2f) mass=%.2f castable=%@",
                             grounded ? "T" : "F", feet.y, target,
                             velocity.x, velocity.y, velocity.z, mass, castable ? "T" : "F"))
            }

            steer(body: body, feet: feet, grounded: grounded,
                  robot: &robot, velocity: velocity, mass: mass, scene: scene)

            if robot.keepsUpright {
                stabiliseUpright(entity: entity)
            }

            respawnIfFallenOffMap(entity: entity, feet: feet, robot: &robot)

            entity.components.set(robot)
        }

        if shouldLog && matched == 0 {
            print("[Robot] ⚠️ system running but query matched 0 robots (component/registration issue)")
        }
    }

    // MARK: - Steering + step-over

    private func steer(
        body: PhysicsDrivable,
        feet: SIMD3<Float>,
        grounded: Bool,
        robot: inout PhysicsRobotComponent,
        velocity: SIMD3<Float>,
        mass: Float,
        scene: Scene
    ) {
        guard let target = robot.targetPosition else {
            // Idle: only damp horizontal drift when grounded; if airborne let it fall.
            if grounded { brakeHorizontal(body: body, velocity: velocity, mass: mass) }
            return
        }

        let toTarget = SIMD3<Float>(target.x - feet.x, 0, target.z - feet.z)
        let distance = simd_length(toTarget)

        if distance <= robot.arriveThreshold {
            brakeHorizontal(body: body, velocity: velocity, mass: mass)
            robot.targetPosition = nil
            return
        }

        let direction = toTarget / distance

        // While airborne, preserve momentum and let gravity own the arc — no forced
        // horizontal drive. This makes falls off ledges look physically believable.
        guard grounded else { return }

        // Impulse to reach cruise velocity in the travel direction. Applying it via
        // the physics body (rather than writing linearVelocity) wakes the body and
        // lets the solver mediate collisions/friction.
        driveHorizontal(body: body,
                        toward: SIMD2<Float>(direction.x, direction.z) * robot.moveSpeed,
                        velocity: velocity, mass: mass)

        faceDirection(entity: body, direction: direction, responsiveness: robot.turnResponsiveness)

        // Step-over: if a low ledge is directly ahead, hop just enough to mount it.
        applyStepAssist(feet: feet, direction: direction, robot: robot,
                        body: body, velocity: velocity, mass: mass, scene: scene)
    }

    /// Applies the impulse needed to bring horizontal velocity to `targetXZ`.
    private func driveHorizontal(body: PhysicsDrivable, toward targetXZ: SIMD2<Float>,
                                 velocity: SIMD3<Float>, mass: Float) {
        let impulse = SIMD3<Float>((targetXZ.x - velocity.x) * mass, 0,
                                   (targetXZ.y - velocity.z) * mass)
        body.applyLinearImpulse(impulse, relativeTo: nil)
    }

    /// Cancels horizontal drift with a single braking impulse.
    private func brakeHorizontal(body: PhysicsDrivable, velocity: SIMD3<Float>, mass: Float) {
        let impulse = SIMD3<Float>(-velocity.x * mass, 0, -velocity.z * mass)
        body.applyLinearImpulse(impulse, relativeTo: nil)
    }

    /// Detects a walkable surface just ahead and, if it sits within the climbable
    /// step height, applies a brief upward impulse so the robot mounts it.
    private func applyStepAssist(
        feet: SIMD3<Float>,
        direction: SIMD3<Float>,
        robot: PhysicsRobotComponent,
        body: PhysicsDrivable,
        velocity: SIMD3<Float>,
        mass: Float,
        scene: Scene
    ) {
        // Only nudge when essentially settled vertically (not mid-hop / mid-fall).
        guard abs(velocity.y) < 0.15 else { return }

        // Probe point just in front of the body, dropped from above.
        let ahead = SIMD3<Float>(feet.x + direction.x * (robot.bodyRadius + 0.012),
                                 feet.y + robot.bodyHeight,
                                 feet.z + direction.z * (robot.bodyRadius + 0.012))
        // `.all`, not `.nearest`: the probe can start inside the robot's own collider,
        // so we need every hit in order to skip the robot and find the surface beneath.
        let hits = scene.raycast(origin: ahead, direction: [0, -1, 0],
                                 length: robot.bodyHeight * 2, query: .all)
        guard let hit = firstNonRobot(hits, robot: body) else { return }

        let stepUp = hit.position.y - feet.y
        if stepUp > Self.minStepHeight && stepUp <= robot.maxStepHeight {
            // Upward impulse to reach the climb-boost velocity; forward motion carries
            // it over, then physics lands it on top of the ledge.
            let impulse = SIMD3<Float>(0, (robot.climbBoost - velocity.y) * mass, 0)
            body.applyLinearImpulse(impulse, relativeTo: nil)
        }
    }

    // MARK: - Ground test

    /// True when a non-robot surface sits within a short distance below the feet.
    private func isGrounded(entity: Entity, feet: SIMD3<Float>,
                            robot: PhysicsRobotComponent, scene: Scene) -> Bool {
        let origin = SIMD3<Float>(feet.x, feet.y + 0.01, feet.z)
        let length = robot.bodyHeight * robot.groundProbeRatio + 0.02
        // `.all`, not `.nearest`: this origin sits inside the robot's own collision box,
        // so `.nearest` would only ever return the robot itself (then filtered → nil),
        // making the robot think it's permanently airborne. `.all` lets us skip the
        // robot and see the ground below it.
        let hits = scene.raycast(origin: origin, direction: [0, -1, 0],
                                 length: length, query: .all)
        return firstNonRobot(hits, robot: entity) != nil
    }

    // MARK: - Fall recovery

    /// If the robot has dropped far below its spawn point it has left the map;
    /// place it back at the start and clear its motion. This is the only spot that
    /// writes a position, and only as an off-world safeguard.
    private func respawnIfFallenOffMap(
        entity: Entity,
        feet: SIMD3<Float>,
        robot: inout PhysicsRobotComponent
    ) {
        guard let start = robot.startPosition else { return }
        if feet.y < start.y - robot.fallRecoveryDepth {
            entity.setPosition(start, relativeTo: nil)
            entity.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
            if var motion = entity.components[PhysicsMotionComponent.self] {
                motion.linearVelocity = .zero
                motion.angularVelocity = .zero
                entity.components.set(motion)
            }
            robot.targetPosition = nil
        }
    }

    // MARK: - Orientation helpers

    private func faceDirection(entity: Entity, direction: SIMD3<Float>, responsiveness: Float) {
        guard simd_length(direction) > 0.0001 else { return }
        let targetYaw = atan2(direction.x, direction.z)
        let desired = simd_quatf(angle: targetYaw, axis: [0, 1, 0])
        let t = max(0, min(1, responsiveness))
        entity.orientation = simd_slerp(entity.orientation, desired, t)
    }

    private func stabiliseUpright(entity: Entity) {
        // Re-read the component so the driving impulse applied this frame is preserved;
        // we only cancel pitch/roll spin and snap orientation back to yaw-only.
        if var motion = entity.components[PhysicsMotionComponent.self] {
            motion.angularVelocity.x = 0
            motion.angularVelocity.z = 0
            entity.components.set(motion)
        }
        let yaw = currentYaw(of: entity.orientation)
        entity.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
    }

    private func currentYaw(of q: simd_quatf) -> Float {
        let forward = q.act(SIMD3<Float>(0, 0, 1))
        return atan2(forward.x, forward.z)
    }

    // MARK: - Raycast filtering

    /// First hit that isn't the robot itself (or one of its children).
    private func firstNonRobot(_ hits: [CollisionCastHit], robot: Entity) -> CollisionCastHit? {
        hits.first { $0.entity.id != robot.id && !$0.entity.isDescendant(of: robot) }
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

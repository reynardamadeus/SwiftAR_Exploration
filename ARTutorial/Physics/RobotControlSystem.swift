//
//  RobotControlSystem.swift
//  ARTutorial
//
//  Drives the robot toward its tap target using physics, never by scripting Y to
//  locomote. Adds two behaviours on top of plain steering:
//
//   • Step-over  – a low obstacle (top ≤ 1/4 of the robot's height) gets a small
//                  upward velocity nudge so the robot mounts it; taller obstacles
//                  are left to block via collision.
//   • Fall       – while airborne the robot keeps its momentum and lets gravity
//                  arc it down naturally (no forced horizontal drive). If it falls
//                  completely off the mapped world it is respawned at its start.
//
//  All vertical motion is produced by the physics solver or by *velocity* nudges;
//  the only place a position is written is the off-map respawn safeguard.
//
//  Reusable RealityKit `System`; register once with `registerSystem()`.
//

import RealityKit
import Foundation

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

    func update(context: SceneUpdateContext) {
        let scene = context.scene
        for entity in scene.performQuery(Self.query) {
            guard
                var robot = entity.components[PhysicsRobotComponent.self],
                var motion = entity.components[PhysicsMotionComponent.self]
            else { continue }

            let feet = entity.position(relativeTo: nil)
            let grounded = isGrounded(entity: entity, feet: feet, robot: robot, scene: scene)

            steer(entity: entity, feet: feet, grounded: grounded,
                  robot: &robot, motion: &motion, scene: scene)

            if robot.keepsUpright {
                stabiliseUpright(entity: entity, motion: &motion)
            }

            respawnIfFallenOffMap(entity: entity, feet: feet, robot: &robot, motion: &motion)

            entity.components.set(motion)
            entity.components.set(robot)
        }
    }

    // MARK: - Steering + step-over

    private func steer(
        entity: Entity,
        feet: SIMD3<Float>,
        grounded: Bool,
        robot: inout PhysicsRobotComponent,
        motion: inout PhysicsMotionComponent,
        scene: Scene
    ) {
        guard let target = robot.targetPosition else {
            // Idle: only damp horizontal drift when grounded; if airborne let it fall.
            if grounded {
                motion.linearVelocity.x = 0
                motion.linearVelocity.z = 0
            }
            return
        }

        let toTarget = SIMD3<Float>(target.x - feet.x, 0, target.z - feet.z)
        let distance = simd_length(toTarget)

        if distance <= robot.arriveThreshold {
            motion.linearVelocity.x = 0
            motion.linearVelocity.z = 0
            robot.targetPosition = nil
            return
        }

        let direction = toTarget / distance

        // While airborne, preserve momentum and let gravity own the arc — no forced
        // horizontal drive. This makes falls off ledges look physically believable.
        guard grounded else { return }

        motion.linearVelocity.x = direction.x * robot.moveSpeed
        motion.linearVelocity.z = direction.z * robot.moveSpeed

        faceDirection(entity: entity, direction: direction, responsiveness: robot.turnResponsiveness)

        // Step-over: if a low ledge is directly ahead, hop just enough to mount it.
        applyStepAssist(feet: feet, direction: direction, robot: robot, motion: &motion,
                        entity: entity, scene: scene)
    }

    /// Detects a walkable surface just ahead and, if it sits within the climbable
    /// step height, applies a brief upward velocity so the robot mounts it.
    private func applyStepAssist(
        feet: SIMD3<Float>,
        direction: SIMD3<Float>,
        robot: PhysicsRobotComponent,
        motion: inout PhysicsMotionComponent,
        entity: Entity,
        scene: Scene
    ) {
        // Only nudge when essentially settled vertically (not mid-hop / mid-fall).
        guard abs(motion.linearVelocity.y) < 0.15 else { return }

        // Probe point just in front of the body, dropped from above.
        let ahead = SIMD3<Float>(feet.x + direction.x * (robot.bodyRadius + 0.012),
                                 feet.y + robot.bodyHeight,
                                 feet.z + direction.z * (robot.bodyRadius + 0.012))
        let hits = scene.raycast(origin: ahead, direction: [0, -1, 0],
                                 length: robot.bodyHeight * 2, query: .nearest)
        guard let hit = firstNonRobot(hits, robot: entity) else { return }

        let stepUp = hit.position.y - feet.y
        if stepUp > Self.minStepHeight && stepUp <= robot.maxStepHeight {
            // Upward velocity to clear the ledge; forward velocity carries it over.
            motion.linearVelocity.y = robot.climbBoost
        }
    }

    // MARK: - Ground test

    /// True when a non-robot surface sits within a short distance below the feet.
    private func isGrounded(entity: Entity, feet: SIMD3<Float>,
                            robot: PhysicsRobotComponent, scene: Scene) -> Bool {
        let origin = SIMD3<Float>(feet.x, feet.y + 0.01, feet.z)
        let length = robot.bodyHeight * robot.groundProbeRatio + 0.02
        let hits = scene.raycast(origin: origin, direction: [0, -1, 0],
                                 length: length, query: .nearest)
        return firstNonRobot(hits, robot: entity) != nil
    }

    // MARK: - Fall recovery

    /// If the robot has dropped far below its spawn point it has left the map;
    /// place it back at the start and clear its motion. This is the only spot that
    /// writes a position, and only as an off-world safeguard.
    private func respawnIfFallenOffMap(
        entity: Entity,
        feet: SIMD3<Float>,
        robot: inout PhysicsRobotComponent,
        motion: inout PhysicsMotionComponent
    ) {
        guard let start = robot.startPosition else { return }
        if feet.y < start.y - robot.fallRecoveryDepth {
            entity.setPosition(start, relativeTo: nil)
            entity.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
            motion.linearVelocity = .zero
            motion.angularVelocity = .zero
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

    private func stabiliseUpright(entity: Entity, motion: inout PhysicsMotionComponent) {
        motion.angularVelocity.x = 0
        motion.angularVelocity.z = 0
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

//
//  CourseEvaluationSystem.swift
//  ARTutorial
//
//  Watches the vehicle each frame and resolves the run into a `RunOutcome` using
//  only physics-derived signals — position, orientation, velocity, time — plus the
//  contact counters the coordinator's collision subscription fills in. It never
//  scripts anything; it only *observes* the simulation the robot drives itself
//  through, exactly like `RobotControlSystem` on the driving side.
//
//  Register once via `bootstrap()`.
//

import RealityKit
import Foundation

final class CourseEvaluationSystem: System {

    private static let query = EntityQuery(where: .has(CourseRunComponent.self)
                                           && .has(PhysicsMotionComponent.self))

    // Thresholds.
    private static let stallSpeed: Float = 0.02        // m/s below this = not moving
    private static let stallLimit: TimeInterval = 2.5  // sustained stall → stuck
    private static let flipAngle: Float = 1.2          // ~69° tilt → flipped

    required init(scene: Scene) {}

    private static var didBootstrap = false
    static func bootstrap() {
        guard !didBootstrap else { return }
        CourseRunComponent.registerComponent()
        ObstacleMarkerComponent.registerComponent()
        FinishLineComponent.registerComponent()
        CourseEvaluationSystem.registerSystem()
        didBootstrap = true
    }

    func update(context: SceneUpdateContext) {
        let dt = context.deltaTime
        for entity in context.scene.performQuery(Self.query) {
            guard
                var run = entity.components[CourseRunComponent.self],
                let motion = entity.components[PhysicsMotionComponent.self],
                !run.isResolved
            else { continue }

            run.elapsed += dt

            // Tilt: angle between the vehicle up-vector and world up.
            let up = entity.orientation.act(SIMD3<Float>(0, 1, 0))
            let tilt = acos(max(-1, min(1, simd_dot(up, SIMD3<Float>(0, 1, 0)))))
            run.maxTiltRadians = max(run.maxTiltRadians, tilt)

            // Distance to finish (horizontal only).
            let p = entity.position(relativeTo: nil)
            let toFinish = SIMD2<Float>(run.finishPoint.x - p.x, run.finishPoint.z - p.z)
            let distance = simd_length(toFinish)

            // Stall accounting.
            let speed = simd_length(SIMD3<Float>(motion.linearVelocity.x, 0, motion.linearVelocity.z))
            run.stalledSeconds = speed < Self.stallSpeed ? run.stalledSeconds + dt : 0

            run.outcome = Self.resolve(run: run, distance: distance, tilt: tilt)
            entity.components.set(run)
        }
    }

    /// First matching condition wins, most-specific first.
    private static func resolve(run: CourseRunComponent, distance: Float, tilt: Float) -> RunOutcome {
        if distance <= run.finishRadius { return .success }
        if tilt >= flipAngle { return .flipped }
        if run.tunnelBlockedHits > 0 && run.stalledSeconds >= stallLimit { return .tooTallForTunnel }
        if run.chassisHitCount > 0 && run.stalledSeconds >= stallLimit { return .chassisCollision }
        if run.stalledSeconds >= stallLimit { return .stuck }
        if run.elapsed >= run.timeLimit { return .timeout }
        return .running
    }
}

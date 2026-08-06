//
//  Mission1EvaluationSystem.swift
//  ARTutorial
//
//  Watches the Mission 1 vehicle each frame and resolves the run into a
//  `Mission1Outcome` using only physics-derived signals — the car's world Y (for
//  elevation gain) and its up-vector (for tilt/flip). It never scripts motion; it
//  only *observes* the simulation that `RobotControlSystem` drives, exactly like
//  `CourseEvaluationSystem` on the obstacle-course side.
//
//  Register once via `bootstrap()`.
//

import RealityKit
import Foundation

final class Mission1EvaluationSystem: System {

    private static let query = EntityQuery(where: .has(Mission1RunComponent.self)
                                           && .has(PhysicsMotionComponent.self))

    required init(scene: Scene) {}

    /// Registers the Mission 1 component + this system exactly once per process.
    private static var didBootstrap = false
    static func bootstrap() {
        guard !didBootstrap else { return }
        Mission1RunComponent.registerComponent()
        Mission1EvaluationSystem.registerSystem()
        didBootstrap = true
    }

    func update(context: SceneUpdateContext) {
        let dt = context.deltaTime
        for entity in context.scene.performQuery(Self.query) {
            guard
                var run = entity.components[Mission1RunComponent.self],
                !run.isResolved
            else { continue }

            run.elapsed += dt

            // Elevation gain: current world Y minus the settled start Y.
            let y = entity.position(relativeTo: nil).y
            run.currentElevationGain = y - run.startElevation
            run.maxElevationGain = max(run.maxElevationGain, run.currentElevationGain)

            // Tilt: angle between the car's up-vector and world up. On the ramp this
            // equals the slope angle (small); a real flip is far larger.
            let up = entity.orientation.act(SIMD3<Float>(0, 1, 0))
            let tilt = acos(max(-1, min(1, simd_dot(up, SIMD3<Float>(0, 1, 0)))))
            run.maxTiltRadians = max(run.maxTiltRadians, tilt)
            let isFlipped = tilt >= run.flipAngle

            // Sustained-flip timer → fail (mission: flipped for 3 s).
            run.flippedSeconds = isFlipped ? run.flippedSeconds + dt : 0

            // Success dwell: elevation reached AND upright, held briefly to reject a
            // transient bounce.
            let successNow = run.currentElevationGain >= run.requiredElevationGain && !isFlipped
            run.successHeldSeconds = successNow ? run.successHeldSeconds + dt : 0

            run.outcome = Self.resolve(run: run)
            entity.components.set(run)
        }
    }

    /// First matching condition wins, most-specific first.
    private static func resolve(run: Mission1RunComponent) -> Mission1Outcome {
        if run.flippedSeconds >= run.flipFailSeconds { return .flipped }
        if run.successHeldSeconds >= run.successHoldSeconds { return .success }
        return .running
    }
}

//
//  Mission1RunComponent.swift
//  ARTutorial
//
//  Per-run telemetry for Mission 1 — "Tanjakan" (drive a virtual car up a ramp).
//  `Mission1EvaluationSystem` writes to it each frame and resolves the attempt.
//  Kept on one component so the whole run is inspectable and reusable, matching the
//  project's "reusable systems over hardcoded" rule (mirrors `CourseRunComponent`).
//
//  Mission 1 rules (from the mission table):
//    • Success — the car's elevation rises by at least `requiredElevationGain`
//      (10 cm in AR metres) AND all wheels are still on the surface (approximated by
//      the body staying upright, i.e. tilt below `flipAngle`).
//    • Fail    — the car is flipped (tilt past `flipAngle`, "not all wheels touching")
//      continuously for `flipFailSeconds` (3 s).
//

import RealityKit
import Foundation

/// How a Mission 1 attempt ended. Most-specific first (see the evaluator).
enum Mission1Outcome: String, Codable, Sendable {
    case running   // still climbing
    case success   // gained +10 cm elevation while upright
    case flipped   // tipped over (not all wheels touching) for 3 s
}

/// Live telemetry + result for one Mission 1 attempt.
struct Mission1RunComponent: Component {

    // MARK: - Rules (tunable)

    /// Elevation the car must gain to pass, in AR metres. 0.10 = the mission's 10 cm.
    var requiredElevationGain: Float

    /// Tilt (radians) beyond which the body counts as "not all wheels touching".
    /// Must sit well above the ramp's own pitch so climbing the slope isn't mistaken
    /// for a flip. ~1.0 rad ≈ 57°.
    var flipAngle: Float

    /// How long the car must stay flipped before the run fails (mission: 3 s).
    var flipFailSeconds: TimeInterval

    /// Short dwell the success condition must hold to reject a transient bounce.
    var successHoldSeconds: TimeInterval

    // MARK: - Captured at spawn

    /// The car's Y at the start of the run; elevation gain is measured against it.
    /// Set by the coordinator once the car has settled on the start pad.
    var startElevation: Float

    // MARK: - Filled during the run

    var elapsed: TimeInterval = 0
    var currentElevationGain: Float = 0
    var maxElevationGain: Float = 0
    var maxTiltRadians: Float = 0
    var flippedSeconds: TimeInterval = 0
    var successHeldSeconds: TimeInterval = 0

    var outcome: Mission1Outcome = .running

    init(
        startElevation: Float = 0,
        requiredElevationGain: Float = 0.10,
        flipAngle: Float = 1.0,
        flipFailSeconds: TimeInterval = 3.0,
        successHoldSeconds: TimeInterval = 0.3
    ) {
        self.startElevation = startElevation
        self.requiredElevationGain = requiredElevationGain
        self.flipAngle = flipAngle
        self.flipFailSeconds = flipFailSeconds
        self.successHoldSeconds = successHoldSeconds
    }

    var isResolved: Bool { outcome != .running }
}

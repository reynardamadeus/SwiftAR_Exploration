//
//  CourseRunComponent.swift
//  ARTutorial
//
//  Per-run telemetry carried on the vehicle. `CourseEvaluationSystem` writes to it
//  each frame; the collision subscription in the coordinator bumps the contact
//  counters. When the run resolves, `FeedbackEngine` reads it to produce advice.
//  Keeping all of this on one component means the whole run is inspectable and
//  reusable, per the project's "reusable systems over hardcoded" rule.
//

import RealityKit
import Foundation

/// How a run ended. Ordered rough-to-specific; the first matching condition wins.
enum RunOutcome: String, Codable, Sendable {
    case running          // not finished yet
    case success          // reached the finish line
    case stuck            // stalled far from the finish (often: wheels slipping)
    case chassisCollision // the body scraped an obstacle (needs clearance)
    case tooTallForTunnel // blocked at a tunnel/bridge opening (needs lower body)
    case flipped          // tipped past the recovery angle
    case timeout          // ran out of time with no clear cause
}

/// Live telemetry + result for one attempt.
struct CourseRunComponent: Component {

    /// World-space finish target the vehicle drives toward.
    var finishPoint: SIMD3<Float>
    /// Horizontal distance under which the vehicle counts as "arrived".
    var finishRadius: Float

    /// Seconds allowed before the run times out.
    var timeLimit: TimeInterval

    // Filled during the run.
    var elapsed: TimeInterval = 0
    var maxTiltRadians: Float = 0
    var stalledSeconds: TimeInterval = 0
    var chassisHitCount: Int = 0
    var tunnelBlockedHits: Int = 0

    var outcome: RunOutcome = .running

    init(finishPoint: SIMD3<Float>, finishRadius: Float = 0.05, timeLimit: TimeInterval = 20) {
        self.finishPoint = finishPoint
        self.finishRadius = finishRadius
        self.timeLimit = timeLimit
    }

    var isResolved: Bool { outcome != .running }
}

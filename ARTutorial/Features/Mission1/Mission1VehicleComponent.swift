//
//  Mission1VehicleComponent.swift
//  ARTutorial
//
//  A raycast-suspension vehicle for Mission 1. Unlike the shared box-driver
//  (`RobotControlSystem`, which shoves a single rigid body through its centre and so
//  tends to topple), this models the car as a chassis riding on four wheels: each
//  wheel casts a ray down and pushes the chassis up with a spring. Because support
//  comes from four corner points, the car self-levels, pitches to follow a ramp, and
//  keeps its wheels on the surface instead of faceplanting.
//
//  `Mission1VehicleSystem` reads this each frame to apply suspension, drive and grip.
//

import RealityKit

/// One wheel: where it attaches under the chassis (local) + its visual entity.
struct Mission1Wheel {
    /// Attach point in chassis-local space (a bottom corner). The suspension ray is
    /// cast downward from here.
    let attach: SIMD3<Float>
    /// The visual wheel entity, repositioned (suspension travel) and spun each frame.
    let visual: Entity
}

/// Locomotion + suspension state for a Mission 1 raycast vehicle.
struct Mission1VehicleComponent: Component {

    var wheels: [Mission1Wheel]

    // MARK: - Suspension (spring-damper per wheel)

    /// Wheel radius (metres) — the ray reaches `restLength + wheelRadius`.
    var wheelRadius: Float
    /// Natural gap between the attach point and the ground contact (metres).
    var restLength: Float
    /// Spring constant (N/m). Higher = stiffer ride, holds the chassis higher.
    var stiffness: Float
    /// Spring damping (N·s/m). Prevents the suspension from bouncing/oscillating.
    var damping: Float

    // MARK: - Drive

    /// World-space point to drive toward (X/Z only), or `nil` when idle.
    var targetPosition: SIMD3<Float>?
    /// Spawn point, for off-map fall recovery.
    var startPosition: SIMD3<Float>?
    /// Cruise speed cap (m/s).
    var maxSpeed: Float
    /// Forward force applied at each grounded wheel (N).
    var driveForce: Float
    /// Sideways grip, 0…1 — how strongly lateral (sideways) slip is cancelled.
    var grip: Float
    /// Horizontal distance at which the car is "arrived" and stops driving.
    var arriveThreshold: Float

    // MARK: - Fall recovery

    /// If the chassis drops this far below `startPosition.y`, respawn it.
    var fallRecoveryDepth: Float

    // MARK: - Visual state

    /// Accumulated wheel-roll angle (radians), advanced by forward speed.
    var spinAngle: Float = 0

    init(
        wheels: [Mission1Wheel],
        wheelRadius: Float = 0.015,
        restLength: Float = 0.03,
        stiffness: Float = 90,
        damping: Float = 6,
        maxSpeed: Float = 0.18,
        driveForce: Float = 0.5,
        grip: Float = 0.6,
        arriveThreshold: Float = 0.03,
        fallRecoveryDepth: Float = 1.5
    ) {
        self.wheels = wheels
        self.wheelRadius = wheelRadius
        self.restLength = restLength
        self.stiffness = stiffness
        self.damping = damping
        self.targetPosition = nil
        self.startPosition = nil
        self.maxSpeed = maxSpeed
        self.driveForce = driveForce
        self.grip = grip
        self.arriveThreshold = arriveThreshold
        self.fallRecoveryDepth = fallRecoveryDepth
    }
}

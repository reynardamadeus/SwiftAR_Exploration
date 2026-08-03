//
//  PhysicsRobotComponent.swift
//  ARTutorial
//
//  Marks an entity as a physics-driven robot and stores its locomotion intent.
//
//  Design note:
//  The robot is a `.dynamic` physics body. We never write its Y position to *move*
//  it — gravity, ramps and edges own vertical motion. This component carries the
//  horizontal goal (a tap target) plus tuning for chasing it, staying upright,
//  stepping over small obstacles, and recovering if it falls off the map.
//

import RealityKit

/// Locomotion intent + tuning for a physics-driven robot.
///
/// `RobotControlSystem` reads this each frame and drives the entity's horizontal
/// velocity toward `targetPosition`, leaving vertical motion to physics.
struct PhysicsRobotComponent: Component {

    // MARK: Goal

    /// World-space point the robot should walk toward, or `nil` when idle.
    /// Only the X/Z of this point is used; Y is owned by the physics simulation.
    var targetPosition: SIMD3<Float>?

    // MARK: Locomotion tuning

    /// Horizontal cruise speed in metres per second (world scale).
    var moveSpeed: Float

    /// Distance (metres, horizontal) at which the robot is "arrived" and stops.
    var arriveThreshold: Float

    /// When `true`, cancels pitch/roll each frame so the robot stays upright
    /// while still turning (yaw) toward its target.
    var keepsUpright: Bool

    /// How quickly the robot yaws to face its travel direction (0…1 per frame).
    var turnResponsiveness: Float

    // MARK: Body metrics (needed for step + fall reasoning)

    /// Approximate collision height of the robot in metres. Drives the step-over
    /// threshold and ground/step probes.
    var bodyHeight: Float

    /// Approximate collision radius (half-width) in metres, used to place the
    /// forward step probe just in front of the body.
    var bodyRadius: Float

    // MARK: Step-over (requirement: mount obstacles below 1/4 of robot height)

    /// Obstacles whose top is at or below `bodyHeight * stepHeightRatio` can be
    /// climbed; taller ones block the robot. Defaults to 1/4 the robot's height.
    var stepHeightRatio: Float

    /// Upward velocity (m/s) applied to mount a detected step. Tuned so the robot
    /// hops just enough to clear a low ledge, then physics lands it on top.
    var climbBoost: Float

    // MARK: Fall handling

    /// Fraction of `bodyHeight` used as the downward "am I standing on something?"
    /// probe length. Below this distance to a surface the robot is grounded.
    var groundProbeRatio: Float

    /// World-space spawn point, captured when the robot is placed. Used to recover
    /// the robot if it falls entirely off the mapped world.
    var startPosition: SIMD3<Float>?

    /// If the robot's feet drop more than this far (metres) below `startPosition`,
    /// it has left the map and is respawned. Large enough that normal table→floor
    /// falls are allowed to play out naturally.
    var fallRecoveryDepth: Float

    init(
        moveSpeed: Float = 0.25,
        arriveThreshold: Float = 0.03,
        keepsUpright: Bool = true,
        turnResponsiveness: Float = 0.2,
        bodyHeight: Float = 0.08,
        bodyRadius: Float = 0.025,
        stepHeightRatio: Float = 0.25,
        climbBoost: Float = 0.55,
        groundProbeRatio: Float = 0.2,
        fallRecoveryDepth: Float = 1.5
    ) {
        self.targetPosition = nil
        self.moveSpeed = moveSpeed
        self.arriveThreshold = arriveThreshold
        self.keepsUpright = keepsUpright
        self.turnResponsiveness = turnResponsiveness
        self.bodyHeight = bodyHeight
        self.bodyRadius = bodyRadius
        self.stepHeightRatio = stepHeightRatio
        self.climbBoost = climbBoost
        self.groundProbeRatio = groundProbeRatio
        self.startPosition = nil
        self.fallRecoveryDepth = fallRecoveryDepth
    }

    /// Maximum climbable step height in metres.
    var maxStepHeight: Float { bodyHeight * stepHeightRatio }
}

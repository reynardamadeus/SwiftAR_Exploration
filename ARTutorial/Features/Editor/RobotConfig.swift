//
//  RobotConfig.swift
//  ARTutorial
//
//  3D Robot Assembly Editor — data model.
//  Pure value type (Codable + Sendable) so it can be passed freely between
//  SwiftUI state and the RealityKit container, and persisted/reloaded later.
//

import Foundation

/// Which of the four wheel positions a tap selected.
enum WheelSlot: String, CaseIterable, Identifiable, Sendable {
    case frontLeft, frontRight, rearLeft, rearRight

    var id: String { rawValue }

    /// Kid-friendly label (Indonesian).
    var displayName: String {
        switch self {
        case .frontLeft:  return "Depan Kiri"
        case .frontRight: return "Depan Kanan"
        case .rearLeft:   return "Belakang Kiri"
        case .rearRight:  return "Belakang Kanan"
        }
    }
}

/// Snapshot of an editable robot. Built from the 3D scene state and usable to
/// rebuild the scene, so it is the single source of truth for the editor.
struct RobotConfig: Codable, Equatable, Sendable {

    struct BodySize: Codable, Equatable, Sendable {
        var length: Float  // X
        var width: Float   // Z
        var height: Float  // Y
    }

    enum WheelType: String, Codable, CaseIterable, Sendable {
        case none       // empty slot
        case smooth     // jalan halus  (Roda Kota)
        case offroad    //              (Roda Pegunungan)
        case heavy      //              (Roda Kuat)

        /// Kid-friendly label (Indonesian).
        var displayName: String {
            switch self {
            case .none:    return "Hapus"
            case .smooth:  return "Roda Kota"
            case .offroad: return "Roda Pegunungan"
            case .heavy:   return "Roda Kuat"
            }
        }
    }

    struct WheelConfig: Codable, Equatable, Sendable {
        var type: WheelType

        // MARK: - Future: physics (weight, friction, radius)
        // These are stubs for the next phase (center of gravity, surface grip,
        // movement simulation). Kept here so later work only changes behavior,
        // not the data shape.
        var weight: Float
        var radius: Float
        var friction: Float
    }

    var bodySize: BodySize

    /// Uniform wheel-size multiplier (kid-adjustable via the "Ukuran Roda" slider).
    var wheelScale: Float

    var frontLeftWheel: WheelConfig
    var frontRightWheel: WheelConfig
    var rearLeftWheel: WheelConfig
    var rearRightWheel: WheelConfig

    static let `default` = RobotConfig(
        bodySize: BodySize(length: 1.2, width: 0.8, height: 0.5),
        wheelScale: 0.1,
        frontLeftWheel:  WheelConfig(type: .smooth, weight: 1.0, radius: 0.12, friction: 0.5),
        frontRightWheel: WheelConfig(type: .smooth, weight: 1.0, radius: 0.12, friction: 0.5),
        rearLeftWheel:   WheelConfig(type: .smooth, weight: 1.0, radius: 0.12, friction: 0.5),
        rearRightWheel:  WheelConfig(type: .smooth, weight: 1.0, radius: 0.12, friction: 0.5)
    )

    /// Read/write a wheel config by slot, for ergonomic SwiftUI binding.
    subscript(slot: WheelSlot) -> WheelConfig {
        get {
            switch slot {
            case .frontLeft:  return frontLeftWheel
            case .frontRight: return frontRightWheel
            case .rearLeft:   return rearLeftWheel
            case .rearRight:  return rearRightWheel
            }
        }
        set {
            switch slot {
            case .frontLeft:  frontLeftWheel = newValue
            case .frontRight: frontRightWheel = newValue
            case .rearLeft:   rearLeftWheel = newValue
            case .rearRight:  rearRightWheel = newValue
            }
        }
    }

    /// Body mass proxy = volume (m³). Used by the center-of-gravity calc.
    var bodyMass: Float { bodySize.length * bodySize.width * bodySize.height }

    /// Mass-weighted center of gravity across the body and the (present) wheels.
    /// `.none` wheels contribute no mass. Used by the 3D marker and the 2D view.
    func centerOfGravity() -> SIMD3<Float> {
        var totalMass: Float = bodyMass
        var moment = bodyMass * RobotGeometry.bodyCenter(bodySize: bodySize)
        for slot in WheelSlot.allCases {
            let wheel = self[slot]
            guard wheel.type != .none else { continue }
            let m = wheel.weight
            totalMass += m
            moment += m * RobotGeometry.slotWorldPosition(slot, bodySize: bodySize)
        }
        return totalMass > 0 ? moment / totalMass : .zero
    }
}

/// Shared layout constants so the 3D builder, the 2D schematic, and the
/// center-of-gravity calculation all agree on where things sit.
enum RobotGeometry {
    /// Height of the body's bottom above the ground — the visible gap.
    static let bodyLift: Float = 0.3
    /// Wheel-center height: wheels sit near the ground, below the lifted body.
    static let wheelY: Float = 0.08

    /// Body center in world space.
    static func bodyCenter(bodySize: RobotConfig.BodySize) -> SIMD3<Float> {
        [0, bodySize.height / 2 + bodyLift, 0]
    }

    /// Bottom-corner world position of a wheel slot for the given body size.
    /// front = +X, rear = -X; right = +Z, left = -Z.
    static func slotWorldPosition(_ slot: WheelSlot, bodySize: RobotConfig.BodySize) -> SIMD3<Float> {
        let halfLength = bodySize.length / 2
        let halfWidth = bodySize.width / 2
        let y = wheelY
        switch slot {
        case .frontLeft:  return [ halfLength, y, -halfWidth]
        case .frontRight: return [ halfLength, y,  halfWidth]
        case .rearLeft:   return [-halfLength, y, -halfWidth]
        case .rearRight:  return [-halfLength, y,  halfWidth]
        }
    }
}

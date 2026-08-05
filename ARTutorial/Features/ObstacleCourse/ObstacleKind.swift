//
//  ObstacleKind.swift
//  ARTutorial
//
//  The small library of *clean* digital obstacles a scanned physical build maps
//  onto. We never reproduce the LEGO geometry — the child's pile of bricks becomes
//  one of these game-like props, scaled to the detected footprint. Keeping the set
//  tiny (four kinds) is what makes the whole scanning problem tractable for an MVP.
//

import Foundation

/// A clean obstacle category. Each carries the pedagogy it teaches so the feedback
/// engine can talk about it in kid terms.
enum ObstacleKind: String, CaseIterable, Codable, Sendable {
    case rock    // static blocker: drive around, or climb if wheels are big enough
    case ramp    // tilted surface: climb via friction + normal force
    case bridge  // raised deck with a gap under it: path/clearance
    case tunnel  // portal with a fixed opening height: vehicle must be short enough

    /// Kid-friendly label (Indonesian, to match the rest of the app's UI).
    var displayName: String {
        switch self {
        case .rock:   return "Batu"
        case .ramp:   return "Tanjakan"
        case .bridge: return "Jembatan"
        case .tunnel: return "Terowongan"
        }
    }

    /// Preset height (metres, world scale) used when a real height can't be
    /// measured from a single non-LiDAR frame. Expressed relative to a ~0.08 m
    /// vehicle so the physics reads sensibly at tabletop scale.
    var presetHeight: Float {
        switch self {
        case .rock:   return 0.05
        case .ramp:   return 0.06
        case .bridge: return 0.09
        case .tunnel: return 0.10
        }
    }

    /// Clearance of the opening a vehicle must fit *under* (tunnels/bridges).
    /// `nil` for solid props that are driven over or around.
    var openingHeight: Float? {
        switch self {
        case .tunnel: return 0.075
        case .bridge: return 0.06
        case .rock, .ramp: return nil
        }
    }

    /// Heuristic used by `ObstacleScanner` to *suggest* a kind from a footprint
    /// before the child confirms it. Long & low → ramp; tall & narrow → tunnel;
    /// otherwise a rock. (The child always has the final say.)
    static func suggestion(footprint: SIMD2<Float>, estimatedHeight: Float) -> ObstacleKind {
        let longSide = max(footprint.x, footprint.y)
        let shortSide = max(min(footprint.x, footprint.y), 0.0001)
        let elongation = longSide / shortSide

        if estimatedHeight < 0.045 && elongation > 1.8 { return .ramp }
        if estimatedHeight > 0.08 && elongation > 2.2 { return .tunnel }
        if estimatedHeight > 0.075 { return .bridge }
        return .rock
    }
}

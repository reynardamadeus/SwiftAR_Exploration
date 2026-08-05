//
//  DetectedObstacle.swift
//  ARTutorial
//
//  The hand-off type between scanning and world-building. Everything the CV /
//  scan stage produces is reduced to this small value type, so the rest of the app
//  never depends on *how* the obstacle was detected. Swapping the detector later
//  (rectangles → foreground mask → LiDAR mesh) only changes who fills this in.
//

import Foundation

/// One region of the physical build, lifted into world space and categorised.
///
/// The footprint is on the table plane; height is either measured (LiDAR) or a
/// preset from `ObstacleKind`. `kind` starts as a *suggestion* and is confirmed by
/// the child before the prop is built.
struct DetectedObstacle: Identifiable, Codable, Sendable {

    let id: UUID

    /// World-space centre of the footprint on the table plane.
    var worldCenter: SIMD3<Float>

    /// Footprint size on the plane: X = width, Y = depth (metres, world scale).
    var footprint: SIMD2<Float>

    /// Yaw of the footprint around world-up (radians), so long props align with the
    /// real object's orientation.
    var yaw: Float

    /// Estimated height (metres). Preset unless a mesh sample provided a real value.
    var estimatedHeight: Float

    /// The category the child confirmed (or the suggested default until they do).
    var kind: ObstacleKind

    /// `true` once the child has confirmed/relabelled this region.
    var isConfirmed: Bool

    init(
        id: UUID = UUID(),
        worldCenter: SIMD3<Float>,
        footprint: SIMD2<Float>,
        yaw: Float = 0,
        estimatedHeight: Float,
        kind: ObstacleKind,
        isConfirmed: Bool = false
    ) {
        self.id = id
        self.worldCenter = worldCenter
        self.footprint = footprint
        self.yaw = yaw
        self.estimatedHeight = estimatedHeight
        self.kind = kind
        self.isConfirmed = isConfirmed
    }

    /// Builds a detection from a raw footprint, choosing a suggested kind and a
    /// preset height for it. Used by the scanner before the child confirms.
    static func suggested(worldCenter: SIMD3<Float>, footprint: SIMD2<Float>, yaw: Float) -> DetectedObstacle {
        let kind = ObstacleKind.suggestion(footprint: footprint, estimatedHeight: 0.06)
        return DetectedObstacle(
            worldCenter: worldCenter,
            footprint: footprint,
            yaw: yaw,
            estimatedHeight: kind.presetHeight,
            kind: kind
        )
    }
}

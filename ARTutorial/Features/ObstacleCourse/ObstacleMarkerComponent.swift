//
//  ObstacleMarkerComponent.swift
//  ARTutorial
//
//  Tags a built prop with the obstacle it represents so the collision + evaluation
//  systems can reason about *what* the vehicle touched (a rock vs. a tunnel arch),
//  rather than treating every static body the same. This is what turns a raw
//  contact event into specific engineering feedback.
//

import RealityKit

/// Marks an entity as a course obstacle and records its kind + opening height.
struct ObstacleMarkerComponent: Component {
    let kind: ObstacleKind
    /// Opening the vehicle must fit under (tunnel/bridge), else `nil`.
    let openingHeight: Float?

    init(kind: ObstacleKind) {
        self.kind = kind
        self.openingHeight = kind.openingHeight
    }
}

/// Marks the entity the vehicle must reach to win.
struct FinishLineComponent: Component {
    init() {}
}

//
//  RobotBuilder.swift
//  ARTutorial
//
//  Owns the persistent RealityKit entity tree for one robot and mutates it in
//  place when the config changes. Tree: root → { body (box + edge outline +
//  4 corner slots), center-of-gravity marker }. Wheels (USDZ via WheelFactory)
//  live inside the slots; `.none` slots hold a tappable ghost.
//

import RealityKit
import UIKit

final class RobotBuilder {

    /// Root anchor. In the editor it sits at the world origin; in AR it is
    /// moved to the tapped surface via `place(at:)`.
    let root: AnchorEntity

    private(set) var bodyEntity: ModelEntity
    private(set) var slots: [WheelSlot: Entity] = [:]

    // Visual helpers.
    private let edgeBars: [ModelEntity]          // 12 thin bars = box edges (rusuk)
    private let cogMarker: ModelEntity           // red sphere at the center of gravity

    private let bodyMaterial = UnlitMaterial(color: UIColor(red: 0.25, green: 0.6, blue: 0.95, alpha: 1))
    private let edgeMaterial = UnlitMaterial(color: UIColor(white: 0.08, alpha: 1))
    private let axleThickness: Float = 0.02

    init() {
        root = AnchorEntity(world: Transform.identity.matrix)

        bodyEntity = ModelEntity()
        bodyEntity.name = "body"
        root.addChild(bodyEntity)

        for slot in WheelSlot.allCases {
            let slotEntity = Entity()
            slotEntity.name = slot.rawValue // tap → slot lookup by name
            bodyEntity.addChild(slotEntity)
            slots[slot] = slotEntity
        }

        edgeBars = (0..<12).map { _ in ModelEntity() }
        for bar in edgeBars { bodyEntity.addChild(bar) }

        cogMarker = ModelEntity(
            mesh: .generateSphere(radius: 0.05),
            materials: [UnlitMaterial(color: UIColor(red: 0.95, green: 0.2, blue: 0.2, alpha: 1))]
        )
        cogMarker.name = "cog"
        root.addChild(cogMarker)
    }

    func attach(to scene: Scene) {
        scene.addAnchor(root)
    }

    // MARK: Body + layout

    /// Resize the body mesh, reposition the slots/edges/axles for the new size.
    func applyBodySize(_ size: RobotConfig.BodySize) {
        let mesh = MeshResource.generateBox(size: [size.length, size.height, size.width])
        bodyEntity.model = ModelComponent(mesh: mesh, materials: [bodyMaterial])
        bodyEntity.position = RobotGeometry.bodyCenter(bodySize: size)

        let halfLength = size.length / 2
        let halfWidth = size.width / 2
        // Wheels sit at wheelY (near the ground), well below the lifted body.
        let slotY = RobotGeometry.wheelY - (size.height / 2 + RobotGeometry.bodyLift)
        slots[.frontLeft]?.position  = [ halfLength, slotY, -halfWidth]
        slots[.frontRight]?.position = [ halfLength, slotY,  halfWidth]
        slots[.rearLeft]?.position   = [-halfLength, slotY, -halfWidth]
        slots[.rearRight]?.position  = [-halfLength, slotY,  halfWidth]

        applyEdgeOutline(size)
    }

    /// Reposition + resize the 12 edge bars that outline the block (rusuk).
    private func applyEdgeOutline(_ size: RobotConfig.BodySize) {
        let specs = Self.edgeSpecs(size, thickness: axleThickness)
        for (bar, spec) in zip(edgeBars, specs) {
            bar.model = ModelComponent(
                mesh: .generateBox(size: spec.size),
                materials: [edgeMaterial]
            )
            bar.position = spec.center
        }
    }

    // MARK: Wheels

    /// Swap the wheel in a slot. `.none` installs a tappable placeholder ghost,
    /// so an empty slot can still be selected and refilled.
    @MainActor func setWheel(type: RobotConfig.WheelType, on slot: WheelSlot, scale: Float) {
        guard let slotEntity = slots[slot] else { return }
        slotEntity.children.forEach { $0.removeFromParent() }
        slotEntity.addChild(WheelFactory.makeWheel(for: type, scaleMultiplier: scale))
    }

    // MARK: Center of gravity

    func updateCenterOfGravity(for config: RobotConfig) {
        cogMarker.position = config.centerOfGravity()
    }

    // MARK: Placement (editor vs AR)

    /// Move the whole robot to a world transform (AR tap-to-place) at real scale.
    /// Body dimensions are already in metres and ARKit's world units are metres,
    /// so a 1:1 scale makes a "1 m" robot render as a true 1 m object on the floor.
    func place(at matrix: simd_float4x4) {
        var transform = Transform(matrix: matrix)
        transform.scale = SIMD3<Float>(repeating: 1.0)
        root.transform = transform
    }

    /// Return the robot to the world origin (editor mode) at real scale.
    func resetToOrigin() {
        var transform = Transform.identity
        transform.scale = SIMD3<Float>(repeating: 1.0)
        root.transform = transform
    }

    // MARK: Collisions

    func regenerateCollisions() {
        root.generateCollisionShapes(recursive: true)
    }

    // MARK: Edge geometry

    private struct EdgeSpec { let center: SIMD3<Float>; let size: SIMD3<Float> }

    private static func edgeSpecs(_ s: RobotConfig.BodySize, thickness t: Float) -> [EdgeSpec] {
        let hx = s.length / 2, hy = s.height / 2, hz = s.width / 2
        return [
            // 4 along X
            .init(center: [0,  hy,  hz], size: [s.length, t, t]),
            .init(center: [0,  hy, -hz], size: [s.length, t, t]),
            .init(center: [0, -hy,  hz], size: [s.length, t, t]),
            .init(center: [0, -hy, -hz], size: [s.length, t, t]),
            // 4 along Y
            .init(center: [ hx, 0,  hz], size: [t, s.height, t]),
            .init(center: [ hx, 0, -hz], size: [t, s.height, t]),
            .init(center: [-hx, 0,  hz], size: [t, s.height, t]),
            .init(center: [-hx, 0, -hz], size: [t, s.height, t]),
            // 4 along Z
            .init(center: [ hx,  hy, 0], size: [t, t, s.width]),
            .init(center: [ hx, -hy, 0], size: [t, t, s.width]),
            .init(center: [-hx,  hy, 0], size: [t, t, s.width]),
            .init(center: [-hx, -hy, 0], size: [t, t, s.width]),
        ]
    }
}

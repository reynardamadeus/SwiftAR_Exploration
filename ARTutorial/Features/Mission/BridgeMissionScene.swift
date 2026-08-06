//
//  BridgeMissionScene.swift
//  ARTutorial
//
//  Builds the bridge-crossing scene from a RobotConfig and two placed endpoints.
//  The car mirrors the 3D-editor's look (same blue body, edge "rusuk" outline, and
//  the chosen wheels) so what the kid designs is what they drive.
//
//    • makeBridge(from: A, to: B, width:) — a block at A, a block at B, and a beam
//      spanning them at bridge height with a GAP underneath. Width is randomized per
//      mission. All three pieces are named "bridge" (wheel raycasts count as "on").
//    • makeCar(from: config) — dynamic body, editor visuals, wheels that can spin.
//      Centred on its own origin; the caller positions/orients it.
//
//  Mission spec: Panjang 30 cm (A→B), Lebar max 5 cm (randomized), Ketinggian 10 cm.
//

import RealityKit
import UIKit

enum BridgeMissionScene {

    /// Mission spec dimensions (metres).
    static let bridgeWidthMax: Float = 0.05    // Z — Lebar (max)
    static let bridgeWidthMin: Float = 0.03    // randomized within [min, max]
    static let bridgeHeight: Float = 0.10      // Y — Ketinggian (top surface)
    static let beamThickness: Float = 0.02
    static let blockSize: Float = 0.06         // footprint of the A/B support blocks

    /// Target span (Panjang). Used by the coordinator to validate A→B.
    static let targetLength: Float = 0.30
    static let lengthTolerance: Float = 0.05

    /// Config metres → mission scale (default car 1.2×0.8×0.5 m → 6×4×2.5 cm).
    static let carScale: Float = 0.05

    /// Same materials as the 3D editor so the car reads as "the one I built".
    private static let bodyMaterial = UnlitMaterial(color: UIColor(red: 0.25, green: 0.6, blue: 0.95, alpha: 1))
    private static let edgeMaterial = UnlitMaterial(color: UIColor(white: 0.08, alpha: 1))

    // MARK: - Bridge

    /// Bridge built in a LOCAL frame: origin at point A (ground level), +X toward B.
    /// The caller positions the root at A and yaws it so +X aligns with A→B.
    ///
    /// Layout: a wide ramp climbs from the ground at A up to bridge height, then a
    /// narrow beam (the challenge) spans to a landing block at B — with a GAP under
    /// the beam, so a car that runs off the side falls to the ground.
    static func makeBridge(length: Float, width: Float) -> Entity {
        let root = Entity()

        // Ramp run (horizontal). Capped so the beam keeps a reasonable length.
        let rampRun = min(0.15, length * 0.6)
        let rampAngle = atan2(bridgeHeight, rampRun)
        let rampLength = sqrt(rampRun * rampRun + bridgeHeight * bridgeHeight)
        let approachWidth: Float = 0.08   // ramp + landing are wider than the beam

        // Ramp: sloped box from (0, 0) up to (rampRun, bridgeHeight). Wide, so any
        // car can climb it.
        let ramp = staticBox(size: [rampLength, beamThickness, approachWidth],
                             color: .systemGray, name: "bridge")
        ramp.position = [rampRun / 2, bridgeHeight / 2, 0]
        ramp.orientation = simd_quatf(angle: rampAngle, axis: [0, 0, 1])
        root.addChild(ramp)

        // Beam: narrow (Lebar), flat at bridge height from the ramp top to B, with a
        // gap underneath. This is the part the car must stay on.
        let beamLen = max(length - rampRun, 0.05)
        let beam = staticBox(size: [beamLen, beamThickness, width],
                             color: .systemBrown, name: "bridge")
        beam.position = [rampRun + beamLen / 2, bridgeHeight - beamThickness / 2, 0]
        root.addChild(beam)

        // Landing block at B (wide), top flush with the beam.
        let landing = staticBox(size: SIMD3<Float>(repeating: blockSize),
                                color: .systemGray, name: "bridge")
        landing.position = [length, bridgeHeight / 2, 0]
        root.addChild(landing)

        // Ground plane: a flat collider at floor level so the car has something to
        // rest on at the start and to fall onto. Translucent so the real floor shows
        // through; NOT named "bridge", so wheels on the ground don't count as "on the
        // bridge" — a car that fell off the beam fails correctly.
        let groundLen = length + 0.20
        let groundSize = SIMD3<Float>(groundLen, 0.02, 0.30)
        let ground = ModelEntity(
            mesh: .generateBox(size: groundSize),
            materials: [SimpleMaterial(color: UIColor.systemGray5.withAlphaComponent(0.25), isMetallic: false)]
        )
        ground.name = "ground"
        let groundShape = ShapeResource.generateBox(size: groundSize)
        ground.components.set(CollisionComponent(shapes: [groundShape]))
        ground.components.set(PhysicsBodyComponent(
            shapes: [groundShape], mass: 1,
            material: .generate(friction: 0.8, restitution: 0), mode: .static
        ))
        ground.position = [length / 2, -0.01, 0]
        root.addChild(ground)

        return root
    }

    // MARK: - Car

    /// Config-driven car that mirrors the 3D editor (blue body + rusuk outline +
    /// chosen wheels). Centred on its own origin (length along +X); the caller
    /// orients it toward B. Carries wheel refs so the system can spin them.
    static func makeCar(from config: RobotConfig) -> Entity {
        let s = carScale
        let bodySize = SIMD3<Float>(config.bodySize.length, config.bodySize.height, config.bodySize.width) * s
        let hx = bodySize.x / 2, hy = bodySize.y / 2, hz = bodySize.z / 2

        let car = ModelEntity(mesh: .generateBox(size: bodySize), materials: [bodyMaterial])
        car.name = "car"

        // Edge outline (12 bars = "rusuk"), matching the editor.
        let t: Float = max(0.02 * s, 0.0015)
        for spec in edgeSpecs(bodySize, thickness: t) {
            let bar = ModelEntity(mesh: .generateBox(size: spec.size), materials: [edgeMaterial])
            bar.position = spec.center
            car.addChild(bar)
        }

        // Physics: body box collider, dynamic.
        let shape = ShapeResource.generateBox(size: bodySize)
        car.components.set(CollisionComponent(shapes: [shape]))
        car.components.set(PhysicsBodyComponent(
            shapes: [shape], mass: 0.2,
            material: .generate(friction: 0.7, restitution: 0), mode: .dynamic
        ))
        car.components.set(PhysicsMotionComponent())

        // Wheels: simple cylinders so size, center, and spin axis are fully under
        // control. (The USDZ wheel has an unpredictable native size/pivot, which made
        // it invisible and orbit off-center.) Size follows the Ukuran Roda slider and
        // the body; axle along X to match the spin axis in BridgeMissionSystem.
        let wheelRadius = max(0.006, config.bodySize.height * s * (0.4 + config.wheelScale * 0.3))
        let wheelWidth  = max(0.004, config.bodySize.width  * s * 0.25)
        let axleOrient = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])  // cylinder axis Y → X
        let placements: [(WheelSlot, SIMD3<Float>)] = [
            (.frontRight, [ hx, -hy,  hz]),
            (.frontLeft,  [ hx, -hy, -hz]),
            (.rearRight,  [-hx, -hy,  hz]),
            (.rearLeft,   [-hx, -hy, -hz]),
        ]
        var wheelOffsets: [SIMD3<Float>] = []
        var wheelEntities: [Entity] = []
        for (slot, corner) in placements {
            guard config[slot].type != .none else { continue }
            let wheel = ModelEntity(
                mesh: .generateCylinder(height: wheelWidth, radius: wheelRadius),
                materials: [UnlitMaterial(color: Self.wheelColor(config[slot].type))]
            )
            wheel.orientation = axleOrient
            wheel.position = corner
            car.addChild(wheel)
            wheelOffsets.append(corner)
            wheelEntities.append(wheel)
        }

        var mission = BridgeMissionComponent()
        mission.wheelOffsets = wheelOffsets.isEmpty ? placements.map { $0.1 } : wheelOffsets
        mission.wheelEntities = wheelEntities
        car.components.set(mission)

        return car
    }

    /// Half-height of the car body (so the caller can rest it on a surface).
    static func carHalfHeight(from config: RobotConfig) -> Float {
        config.bodySize.height * carScale / 2
    }

    /// Cylinder colour per tire type (cosmetic; differentiates Roda Kota/Pegunungan/Kuat).
    private static func wheelColor(_ type: RobotConfig.WheelType) -> UIColor {
        switch type {
        case .none:    return .clear
        case .smooth:  return UIColor(white: 0.85, alpha: 1)
        case .offroad: return UIColor(red: 0.38, green: 0.26, blue: 0.15, alpha: 1)
        case .heavy:   return UIColor(white: 0.22, alpha: 1)
        }
    }

    // MARK: - Helpers

    private static func staticBox(size: SIMD3<Float>, color: UIColor, name: String) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateBox(size: size),
            materials: [SimpleMaterial(color: color.withAlphaComponent(0.95), isMetallic: false)]
        )
        entity.name = name
        let shape = ShapeResource.generateBox(size: size)
        entity.components.set(CollisionComponent(shapes: [shape]))
        entity.components.set(PhysicsBodyComponent(
            shapes: [shape], mass: 1,
            material: .generate(friction: 0.9, restitution: 0), mode: .static
        ))
        return entity
    }

    private struct EdgeSpec { let center: SIMD3<Float>; let size: SIMD3<Float> }

    private static func edgeSpecs(_ s: SIMD3<Float>, thickness t: Float) -> [EdgeSpec] {
        let hx = s.x / 2, hy = s.y / 2, hz = s.z / 2
        return [
            .init(center: [0,  hy,  hz], size: [s.x, t, t]),
            .init(center: [0,  hy, -hz], size: [s.x, t, t]),
            .init(center: [0, -hy,  hz], size: [s.x, t, t]),
            .init(center: [0, -hy, -hz], size: [s.x, t, t]),
            .init(center: [ hx, 0,  hz], size: [t, s.y, t]),
            .init(center: [ hx, 0, -hz], size: [t, s.y, t]),
            .init(center: [-hx, 0,  hz], size: [t, s.y, t]),
            .init(center: [-hx, 0, -hz], size: [t, s.y, t]),
            .init(center: [ hx,  hy, 0], size: [t, t, s.z]),
            .init(center: [ hx, -hy, 0], size: [t, t, s.z]),
            .init(center: [-hx,  hy, 0], size: [t, t, s.z]),
            .init(center: [-hx, -hy, 0], size: [t, t, s.z]),
        ]
    }
}

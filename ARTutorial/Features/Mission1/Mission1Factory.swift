//
//  Mission1Factory.swift
//  ARTutorial
//
//  Assembles the Mission 1 — "Tanjakan" — scene: a ground strip, a start pad, a
//  ramp rising to a raised platform, and the config-driven vehicle at the bottom,
//  all under one root ready to attach to an `AnchorEntity`.
//
//  The geometry reuses the proven static-box + tilted-ramp pattern from
//  `PhysicsSceneFactory`. The vehicle is a chassis riding on four raycast wheels
//  (see `Mission1VehicleSystem`) — not the shared single-box driver, which shoves a
//  body through its centre and topples on inclines. The anchor still needs a
//  `PhysicsSimulationComponent` (set by the coordinator).
//
//  Layout (local, along +X): vehicle start at −X on the ground, ramp centred at the
//  origin, raised platform at +X. The car drives up the ramp toward the platform;
//  when its elevation has risen enough while upright, the run passes.
//

import RealityKit
import UIKit
import Combine

/// The assembled Mission 1 scene plus the handles the coordinator needs.
struct Mission1Scene {
    /// Root holding ground + pad + ramp + platform + vehicle.
    let root: Entity
    /// The dynamic chassis (carries `Mission1VehicleComponent` + `Mission1RunComponent`).
    let vehicle: Entity
    /// Local-space point the vehicle drives toward (top of the ramp / platform).
    let targetPoint: SIMD3<Float>
}

enum Mission1Factory {

    // MARK: - Tunables (world-scale metres; tabletop feel, ~8 cm vehicle)

    /// Height the platform top sits above the ground. Kept modest (paired with a
    /// long `rampRun`) so the incline is shallow enough for the car to actually
    /// climb; the success threshold is derived from this (see `makeScene`).
    static let platformHeight: Float = 0.08
    /// Horizontal run of the ramp from bottom to top. Longer = gentler slope.
    /// The slope must stay shallow enough that the surface just ahead of the car
    /// rises less than its step-assist ceiling (~1/4 of body height), or it can't
    /// ratchet up. 0.08 rise over 0.40 run ≈ 11°, which climbs reliably.
    static let rampRun: Float = 0.40
    /// Width (Z) shared by the ground, ramp and platform.
    private static let laneWidth: Float = 0.30

    private static let surfaceMaterial = PhysicsMaterialResource.generate(friction: 0.9, restitution: 0.0)

    /// Retains in-flight `wheel.usdz` loads so their async completions aren't
    /// cancelled before they can swap the real model in for the placeholder disc.
    private static var wheelLoadTokens: [AnyCancellable] = []

    /// Toy-scale starter car sized for the ramp. The shared `RobotConfig.default`
    /// is authored in editor units (≈ metres), which makes a ~1.2 m car that dwarfs
    /// a 30 cm ramp — so Mission 1 uses its own small body. `bodySize` sets the
    /// chassis (metres); the tyre type feeds the wheels' lateral grip. (`wheelScale`
    /// is unused here — the raycast wheels set their own radius/clearance.)
    static var starterConfig: RobotConfig {
        let wheel = RobotConfig.WheelConfig(type: .smooth, weight: 1.0, radius: 0.02, friction: 0.45)
        return RobotConfig(
            // Low, wide, flat chassis → low centre of gravity → stable on the ramp.
            bodySize: .init(length: 0.14, width: 0.12, height: 0.03),
            wheelScale: 0.03,
            frontLeftWheel:  wheel,
            frontRightWheel: wheel,
            rearLeftWheel:   wheel,
            rearRightWheel:  wheel
        )
    }

    // MARK: - Assembly

    /// Builds the Mission 1 scene from the child's current vehicle design.
    static func makeScene(config: RobotConfig) -> Mission1Scene {
        // Drop any wheel loads still pending from a previous (now-discarded) build;
        // this build appends its own tokens below.
        wheelLoadTokens.removeAll()

        let root = Entity()

        // Key X positions along the lane.
        let rampBottomX = -rampRun / 2
        let rampTopX =  rampRun / 2
        let startX = rampBottomX - 0.15          // vehicle start, on the ground
        let platformLength: Float = 0.20
        let platformCenterX = rampTopX + platformLength / 2

        // Ground strip spanning start → platform, top surface at y = 0.
        let groundMinX = startX - 0.05
        let groundMaxX = platformCenterX + platformLength / 2 + 0.05
        let groundLength = groundMaxX - groundMinX
        let ground = staticBox(size: [groundLength, 0.02, laneWidth + 0.04],
                               color: UIColor.systemGray4.withAlphaComponent(0.9))
        ground.position = [(groundMinX + groundMaxX) / 2, -0.01, 0]
        root.addChild(ground)

        // Start pad under the vehicle (visual cue for where the run begins).
        let startPad = staticBox(size: [0.12, 0.02, laneWidth],
                                 color: UIColor.systemGreen.withAlphaComponent(0.9))
        startPad.position = [startX, 0.001, 0]
        root.addChild(startPad)

        // Ramp: a thin static box tilted about +Z so its top face rises toward +X,
        // bridging the ground (y = 0) up to the platform top (y = platformHeight).
        let rampAngle = atan2(platformHeight, rampRun)
        let ramp = staticBox(size: [rampRun, 0.02, laneWidth],
                             color: UIColor.systemOrange.withAlphaComponent(0.95))
        ramp.position = [0, platformHeight / 2, 0]
        ramp.orientation = simd_quatf(angle: rampAngle, axis: [0, 0, 1])
        root.addChild(ramp)

        // Raised platform the car parks on, top at y = platformHeight.
        let platform = staticBox(size: [platformLength, 0.02, laneWidth],
                                 color: UIColor.systemTeal.withAlphaComponent(0.9))
        platform.position = [platformCenterX, platformHeight - 0.01, 0]
        root.addChild(platform)

        // Vehicle: a chassis riding on four raycast wheels (see Mission1VehicleSystem).
        // Built here rather than via VehicleFactory, whose single box driven through
        // its centre topples on inclines. Spawned just above the pad so it settles
        // onto its suspension.
        let vehicle = makeVehicle(config: config)
        vehicle.position = [startX, 0.05, 0]

        // Drive target: the platform centre at the top of the climb (X/Z only).
        let targetPoint = SIMD3<Float>(platformCenterX, platformHeight, 0)

        // Mission telemetry. Success threshold is tied to the ramp height so the car
        // must genuinely reach near the top. `startElevation` is finalised by the
        // coordinator once the car has settled on its wheels.
        vehicle.components.set(Mission1RunComponent(
            startElevation: vehicle.position.y,
            requiredElevationGain: platformHeight - 0.02
        ))
        root.addChild(vehicle)

        return Mission1Scene(root: root, vehicle: vehicle, targetPoint: targetPoint)
    }

    // MARK: - Vehicle (chassis on four raycast wheels)

    /// Builds a chassis (dynamic box body) resting on four visual wheels, wired for
    /// `Mission1VehicleSystem`. The chassis box is the only collider (for obstacle
    /// contact); ground contact is handled per-wheel by the system's downward rays.
    private static func makeVehicle(config: RobotConfig) -> Entity {
        let chassis = RobotEntity()

        let b = config.bodySize
        let bodySize = SIMD3<Float>(b.length, b.height, b.width)

        // Visual + collider hull.
        let hull = ModelEntity(
            mesh: .generateBox(size: bodySize),
            materials: [SimpleMaterial(color: UIColor(red: 0.25, green: 0.6, blue: 0.95, alpha: 1),
                                       isMetallic: false)]
        )
        chassis.addChild(hull)

        let shape = ShapeResource.generateBox(size: bodySize)
        chassis.components.set(CollisionComponent(shapes: [shape]))
        chassis.components.set(PhysicsBodyComponent(
            shapes: [shape],
            mass: 0.5,
            material: .generate(friction: 0.4, restitution: 0.0),
            mode: .dynamic
        ))
        chassis.components.set(PhysicsMotionComponent())

        // Four wheels at the bottom corners.
        let radius: Float = 0.015
        let insetX = bodySize.x * 0.32
        let insetZ = bodySize.z * 0.5          // at the hull sides
        let axleY = -bodySize.y / 2            // chassis underside
        let wheelColor = UIColor(white: 0.12, alpha: 1)

        var wheels: [Mission1Wheel] = []
        for sx in [Float(1), -1] {
            for sz in [Float(1), -1] {
                let attach = SIMD3<Float>(sx * insetX, axleY, sz * insetZ)
                let visual = makeWheel(radius: radius, color: wheelColor)
                visual.position = attach
                chassis.addChild(visual)
                wheels.append(Mission1Wheel(attach: attach, visual: visual))
            }
        }

        // Lateral grip carries over the child's tyre choice (smooth ≈ 0.45, etc.).
        let grip = min(1, VehicleFactory.friction(for: VehicleFactory.dominantTire(config)))
        chassis.components.set(Mission1VehicleComponent(
            wheels: wheels,
            wheelRadius: radius,
            restLength: 0.025,
            grip: grip
        ))
        return chassis
    }

    /// A wheel hub that the vehicle system positions and spins (about Z). It contains
    /// the real `wheel.usdz` model, sized to the wheel diameter; until that finishes
    /// loading a placeholder disc stands in. Children are oriented so their axle lies
    /// along Z, so spinning the hub about Z rolls the wheel.
    private static func makeWheel(radius: Float, color: UIColor) -> Entity {
        let hub = Entity()

        // Placeholder disc (axle along Z) shown until the USDZ resolves.
        let placeholder = ModelEntity(
            mesh: .generateCylinder(height: 0.01, radius: radius),
            materials: [SimpleMaterial(color: color, isMetallic: false)]
        )
        placeholder.name = "placeholder"
        placeholder.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        hub.addChild(placeholder)

        // Load bundled wheel.usdz, scale it to the wheel diameter, and swap it in.
        let targetDiameter = radius * 2
        let token = ModelEntity.loadModelAsync(named: "wheel")
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    print("Mission1: failed to load wheel.usdz — \(error)")
                }
            }, receiveValue: { [weak hub] model in
                guard let hub else { return }
                let bounds = model.visualBounds(relativeTo: model)
                let maxExtent = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
                let scale = maxExtent > 0 ? targetDiameter / maxExtent : 1
                model.scale = SIMD3<Float>(repeating: scale)
                model.position = -bounds.center * scale   // recentre on the hub origin
                hub.children.filter { $0.name == "placeholder" }.forEach { $0.removeFromParent() }
                hub.addChild(model)
            })
        wheelLoadTokens.append(token)

        return hub
    }

    // MARK: - Shared builder (mirrors PhysicsSceneFactory.makeStaticBox)

    private static func staticBox(size: SIMD3<Float>, color: UIColor) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateBox(size: size),
            materials: [SimpleMaterial(color: color, isMetallic: false)]
        )
        let shape = ShapeResource.generateBox(size: size)
        entity.components.set(CollisionComponent(shapes: [shape]))
        entity.components.set(PhysicsBodyComponent(
            shapes: [shape],
            mass: 1,               // ignored for static bodies, required by init
            material: surfaceMaterial,
            mode: .static
        ))
        return entity
    }
}

//
//  BridgeMissionSystem.swift
//  ARTutorial
//
//  Drives the mission car along the straight line A→B and evaluates the mission:
//
//    Success : moved ≥ 0.30 m AND all 4 wheels still on the bridge.
//    Fail    : fewer than 4 wheels on the bridge for 3 s (fell off / flipped), OR
//              moved < 0.05 m for 10 s (stuck).
//
//  Driving is horizontal-velocity only (straight toward B). Orientation is left to
//  physics — the car is NOT forced upright, so if it runs off the narrow beam it
//  tips and falls into the gap naturally. Whether it stays on depends on the car's
//  WIDTH (do all four wheels sit over the 5 cm bridge?), which is the challenge.
//
//  Reusable RealityKit `System`; register once via `bootstrap()`.
//

import RealityKit
import Foundation
import Combine
import QuartzCore

// MARK: - Mission status (UI-facing)

enum MissionStatus: Equatable {
    case placeA       // tap to place point A
    case placeB       // tap to place point B
    case design       // A & B placed + validated; prompt to build the car
    case ready        // car designed; show "Bangun Jembatan"
    case armed        // bridge built, car at A; show "Mulai"
    case driving      // car is driving A→B
    case success
    case failFlipped
    case failStuck
}

/// App-wide mission readout. The system writes; SwiftUI reads.
final class MissionState: ObservableObject {
    static let shared = MissionState()

    @Published var status: MissionStatus = .placeA
    @Published var distanceMeters: Float = 0
    @Published var wheelsOnBridge: Int = 0
    @Published var spanMeters: Float = 0              // measured A→B length
    @Published var spanOK: Bool = false               // does it meet the 30 cm Panjang spec?
    @Published var bridgeWidthMeters: Float = 0.05    // randomized Lebar per mission
    @Published var message: String = "Sentuh lantai untuk meletakkan titik A"

    private init() {}

    func reset() {
        status = .placeA
        distanceMeters = 0
        wheelsOnBridge = 0
        spanMeters = 0
        spanOK = false
        message = "Sentuh lantai untuk meletakkan titik A"
    }
}

// MARK: - Per-car mission data

struct BridgeMissionComponent: Component {
    /// World-space point B the car drives toward (straight line). nil = idle.
    var targetB: SIMD3<Float>?
    /// Wheel offsets relative to the car entity (for downward contact raycasts).
    var wheelOffsets: [SIMD3<Float>] = []
    /// Wheel entity refs (for the spin animation while driving).
    var wheelEntities: [Entity] = []
    /// World-space start point A (captured when driving begins).
    var startA: SIMD3<Float> = .zero

    var finished: Bool = false

    // Detection bookkeeping
    var offBridgeDuration: TimeInterval = 0
    var lastMoveRefPos: SIMD3<Float> = .zero
    var lastMoveTime: TimeInterval = 0

    // Tunables
    var moveSpeed: Float = 0.16         // m/s — enough to climb the entry ramp
    var arriveThreshold: Float = 0.02

    /// Mission thresholds (from the design spec).
    static let successDistance: Float = 0.30
    static let flipTimeLimit: TimeInterval = 3
    static let stuckDistance: Float = 0.05
    static let stuckTimeLimit: TimeInterval = 10
}

// MARK: - System

final class BridgeMissionSystem: System {

    private static let query = EntityQuery(where: .has(BridgeMissionComponent.self)
                                           && .has(PhysicsMotionComponent.self))

    private static var didBootstrap = false
    static func bootstrap() {
        guard !didBootstrap else { return }
        BridgeMissionComponent.registerComponent()
        BridgeMissionSystem.registerSystem()
        didBootstrap = true
    }

    required init(scene: Scene) {}

    func update(context: SceneUpdateContext) {
        let scene = context.scene
        let now = CACurrentMediaTime()

        for entity in scene.performQuery(Self.query) {
            guard var mission = entity.components[BridgeMissionComponent.self],
                  var motion = entity.components[PhysicsMotionComponent.self],
                  !mission.finished else { continue }

            let pos = entity.position(relativeTo: nil)
            let wheelsOn = countWheelsOnBridge(entity: entity, mission: mission, scene: scene)

            // Begin driving bookkeeping on the first frame a target exists.
            if mission.targetB != nil && mission.lastMoveTime == 0 {
                mission.startA = pos
                mission.lastMoveRefPos = pos
                mission.lastMoveTime = now
                MissionState.shared.status = .driving
            }

            // Drive toward B, but ALONG the surface: project the direction onto the
            // ground's tangent plane so the velocity points up the ramp instead of
            // horizontally into it (which stalls on friction). The car is otherwise
            // left to physics, so it still falls off the beam if it runs off the side.
            if let target = mission.targetB {
                let toTarget = SIMD3<Float>(target.x - pos.x, 0, target.z - pos.z)
                let dist = simd_length(toTarget)
                if dist <= mission.arriveThreshold {
                    motion.linearVelocity = .zero
                } else {
                    let horizontal = toTarget / dist
                    let n = groundNormal(entity: entity, scene: scene)
                    let projected = horizontal - n * simd_dot(horizontal, n)
                    let dir = simd_length(projected) > 0.001 ? simd_normalize(projected) : horizontal
                    motion.linearVelocity = dir * mission.moveSpeed
                }
            } else {
                motion.linearVelocity = .zero
            }

            // Spin the wheels proportional to forward speed. Rolling forward (car +X)
            // is a negative rotation about the +Z axle, hence axis [0, 0, -1].
            let speed = simd_length(SIMD2<Float>(motion.linearVelocity.x, motion.linearVelocity.z))
            if speed > 0.001 {
                let spin = simd_quatf(angle: speed * Float(context.deltaTime) * 10, axis: [1, 0, 0])
                for wheel in mission.wheelEntities {
                    wheel.orientation = spin * wheel.orientation
                }
            }

            // Distance travelled from A (horizontal).
            let distance = simd_length(SIMD2<Float>(pos.x - mission.startA.x,
                                                    pos.z - mission.startA.z))

            // Stuck detection: remember the last position we moved >5 cm from.
            if mission.targetB != nil && !mission.finished {
                let moved = simd_length(SIMD2<Float>(pos.x - mission.lastMoveRefPos.x,
                                                     pos.z - mission.lastMoveRefPos.z))
                if moved > BridgeMissionComponent.stuckDistance {
                    mission.lastMoveRefPos = pos
                    mission.lastMoveTime = now
                }
            }

            // Evaluate win / lose (only while driving).
            if mission.targetB != nil && !mission.finished {
                if distance >= BridgeMissionComponent.successDistance && wheelsOn == 4 {
                    finish(mission: &mission,
                           status: .success,
                           message: "Berhasil! ✅ Mobil menyeberang dengan aman (\(Int(distance * 100)) cm)")
                } else if wheelsOn < 4 {
                    mission.offBridgeDuration += context.deltaTime
                    if mission.offBridgeDuration >= BridgeMissionComponent.flipTimeLimit {
                        finish(mission: &mission,
                               status: .failFlipped,
                               message: "Gagal! ❌ Roda tidak menyentuh jembatan (terjungkal / jatuh)")
                    }
                } else {
                    mission.offBridgeDuration = 0
                }

                if !mission.finished,
                   now - mission.lastMoveTime > BridgeMissionComponent.stuckTimeLimit {
                    finish(mission: &mission,
                           status: .failStuck,
                           message: "Gagal! ❌ Mobil macet (tidak bergerak >10 detik)")
                }
            }

            entity.components.set(motion)
            entity.components.set(mission)

            // Publish readout.
            MissionState.shared.distanceMeters = distance
            MissionState.shared.wheelsOnBridge = wheelsOn
        }
    }

    // MARK: - Outcome

    private func finish(mission: inout BridgeMissionComponent,
                        status: MissionStatus, message: String) {
        mission.finished = true
        mission.targetB = nil
        MissionState.shared.status = status
        MissionState.shared.message = message
    }

    // MARK: - Wheel contact

    /// Raycast straight down from each wheel; a wheel is "on plane" if the first
    /// non-car hit is the bridge (beam or end blocks, all named "bridge").
    private func countWheelsOnBridge(entity: Entity, mission: BridgeMissionComponent,
                                     scene: Scene) -> Int {
        let worldPos = entity.position(relativeTo: nil)
        let orient = entity.orientation(relativeTo: nil)
        var on = 0
        for offset in mission.wheelOffsets {
            let wheelWorld = worldPos + orient.act(offset)
            let origin = SIMD3<Float>(wheelWorld.x, wheelWorld.y + 0.02, wheelWorld.z)
            let hits = scene.raycast(origin: origin, direction: [0, -1, 0],
                                     length: 0.06, query: .all)
            if let hit = firstNonCar(hits, car: entity), hit.entity.name == "bridge" {
                on += 1
            }
        }
        return on
    }

    private func firstNonCar(_ hits: [CollisionCastHit], car: Entity) -> CollisionCastHit? {
        hits.first { !$0.entity.isDescendant(of: car) && $0.entity.id != car.id }
    }

    /// Surface normal directly under the car (downward raycast), used to drive along
    /// slopes. Falls back to straight up if nothing is hit.
    private func groundNormal(entity: Entity, scene: Scene) -> SIMD3<Float> {
        let origin = entity.position(relativeTo: nil) + SIMD3<Float>(0, 0.02, 0)
        let hits = scene.raycast(origin: origin, direction: [0, -1, 0], length: 0.12, query: .all)
        let hit = firstNonCar(hits, car: entity)
        return hit?.normal ?? SIMD3<Float>(0, 1, 0)
    }
}

private extension Entity {
    /// Whether this entity is anywhere below `ancestor` in the hierarchy.
    func isDescendant(of ancestor: Entity) -> Bool {
        var node = parent
        while let current = node {
            if current.id == ancestor.id { return true }
            node = current.parent
        }
        return false
    }
}

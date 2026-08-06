//
//  Mission1Coordinator.swift
//  ARTutorial
//
//  Orchestrates one Mission 1 attempt, keeping AR/session concerns out of the view
//  (same role as `ObstacleCourseCoordinator`, but there is no scan/confirm phase —
//  the ramp is authored, not scanned):
//
//    place → build → run → evaluate → (reset)
//
//  It anchors the authored ramp scene at the table, drives the chassis-on-wheels
//  vehicle up it via `Mission1VehicleSystem`, and polls `Mission1RunComponent` each
//  frame to surface the resolved `Mission1Outcome` to SwiftUI.
//

import RealityKit
import ARKit
import Combine
import SwiftUI

enum Mission1Phase: Equatable {
    case placing   // looking for a surface; tap "Build"
    case ready     // ramp built; tap "Start"
    case running
    case finished  // outcome available
}

@MainActor
final class Mission1Coordinator: ObservableObject {

    weak var arView: ARView?

    @Published var phase: Mission1Phase = .placing
    @Published var outcome: Mission1Outcome?

    /// The child's current vehicle design. Starts from a toy-scale car sized for the
    /// ramp (see `Mission1Factory.starterConfig`) rather than the metre-scale
    /// `RobotConfig.default`.
    @Published var config: RobotConfig = Mission1Factory.starterConfig

    private var scene: Mission1Scene?
    private var anchor: AnchorEntity?
    private var pollTimer: Cancellable?

    init() {
        Mission1VehicleSystem.bootstrap()
        Mission1EvaluationSystem.bootstrap()
    }

    // MARK: - Build

    /// Anchors a fresh ramp scene on the nearest horizontal plane in front of the
    /// camera and settles the vehicle on the start pad (no drive target yet).
    func buildScene() {
        guard let arView else { return }
        teardown()

        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        let hit = arView.raycast(from: center, allowing: .estimatedPlane, alignment: .horizontal).first
        let t = hit?.worldTransform.columns.3
        let world = t.map { SIMD3<Float>($0.x, $0.y, $0.z) } ?? SIMD3<Float>(0, 0, -0.5)

        let anchor = AnchorEntity(world: world)
        let built = Mission1Factory.makeScene(config: config)
        anchor.addChild(built.root)
        anchor.components.set(PhysicsSimulationComponent()) // simulate this subtree
        arView.scene.addAnchor(anchor)

        // Record the spawn in world space for fall recovery, but leave the drive
        // target nil so the car stays put until the child taps "Start".
        if var vc = built.vehicle.components[Mission1VehicleComponent.self] {
            vc.startPosition = built.vehicle.position(relativeTo: nil)
            vc.targetPosition = nil
            built.vehicle.components.set(vc)
        }

        self.anchor = anchor
        self.scene = built
        outcome = nil
        phase = .ready
    }

    // MARK: - Run

    /// "Start": capture the settled elevation as the baseline, point the car at the
    /// top of the ramp, and begin polling the outcome.
    func startRun() {
        guard let built = scene else { return }
        let vehicle = built.vehicle

        // Baseline elevation = the car's current (settled) world Y.
        let settledY = vehicle.position(relativeTo: nil).y
        if var run = vehicle.components[Mission1RunComponent.self] {
            run.startElevation = settledY
            vehicle.components.set(run)
        }

        // Drive target in world space (top of the ramp / platform).
        let targetWorld = built.root.convert(position: built.targetPoint, to: nil)
        if var vc = vehicle.components[Mission1VehicleComponent.self] {
            vc.targetPosition = targetWorld
            vehicle.components.set(vc)
        }

        outcome = nil
        phase = .running
        pollTimer = Timer.publish(every: 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.pollOutcome() }
    }

    private func pollOutcome() {
        guard let vehicle = scene?.vehicle,
              let run = vehicle.components[Mission1RunComponent.self],
              run.isResolved else { return }
        pollTimer?.cancel(); pollTimer = nil
        outcome = run.outcome
        phase = .finished
    }

    /// Retry with the current design unchanged.
    func reset() { buildScene() }

    // MARK: - Teardown

    func teardown() {
        pollTimer?.cancel(); pollTimer = nil
        anchor?.removeFromParent()
        anchor = nil
        scene = nil
    }
}

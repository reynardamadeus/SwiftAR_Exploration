//
//  ObstacleCourseCoordinator.swift
//  ARTutorial
//
//  Orchestrates the full loop for one course, keeping AR/session concerns out of
//  the views (same role as `PhysicsPlaygroundCoordinator`):
//
//    scan → confirm → build → run → evaluate → feedback → (redesign) → run again
//
//  It owns the collision subscription that *classifies* contacts (chassis-vs-rock,
//  body-vs-tunnel) into the vehicle's `CourseRunComponent`, and polls that component
//  each frame to surface the resolved `RunOutcome` + feedback to SwiftUI.
//

import RealityKit
import ARKit
import Combine
import SwiftUI

enum CoursePhase: Equatable {
    case scanning   // pointing at the physical build
    case confirming // reviewing/relabelling detected regions
    case ready      // course built; tap to start the run
    case running
    case finished   // outcome + feedback available
}

@MainActor
final class ObstacleCourseCoordinator: ObservableObject {

    weak var arView: ARView?

    @Published var phase: CoursePhase = .scanning
    @Published var detections: [DetectedObstacle] = []
    @Published var feedback: EngineeringFeedback?

    /// The child's current vehicle design (shared with the editor).
    @Published var config: RobotConfig = .default

    private let scanner = ObstacleScanner()
    private var course: ObstacleCourse?
    private var anchor: AnchorEntity?
    private var subscriptions: [Cancellable] = []
    private var pollTimer: Cancellable?

    init() {
        RobotControlSystem.bootstrap()
        CourseEvaluationSystem.bootstrap()
    }

    // MARK: - Scan → confirm

    /// "Scan": segment the current frame into candidate regions for confirmation.
    func scan() {
        guard let arView else { return }
        detections = scanner.detectObstacles(in: arView)
        phase = detections.isEmpty ? .scanning : .confirming
    }

    /// Child relabels a region (tap a category chip in the confirm UI).
    func relabel(_ id: DetectedObstacle.ID, to kind: ObstacleKind) {
        guard let i = detections.firstIndex(where: { $0.id == id }) else { return }
        detections[i].kind = kind
        detections[i].estimatedHeight = kind.presetHeight
        detections[i].isConfirmed = true
    }

    // MARK: - Build

    /// "Build course": anchor a fresh course at the table in front of the camera.
    func buildCourse() {
        guard let arView else { return }
        teardown()

        // Anchor on the nearest detected horizontal plane (centre of the view).
        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        let origin = arView.raycast(from: center, allowing: .estimatedPlane, alignment: .horizontal).first
        let t = origin?.worldTransform.columns.3
        let world = t.map { SIMD3<Float>($0.x, $0.y, $0.z) } ?? SIMD3<Float>(0, 0, -0.5)

        let anchor = AnchorEntity(world: world)
        let built = CourseFactory.makeCourse(obstacles: detections, config: config)
        anchor.addChild(built.root)
        anchor.components.set(PhysicsSimulationComponent()) // simulate this subtree
        arView.scene.addAnchor(anchor)

        // The course is built in local coordinates, but the driving + evaluation
        // systems reason in world space (like PhysicsPlaygroundCoordinator). Now that
        // the subtree has a real world transform, rewrite the finish/target/spawn in
        // world coordinates.
        let finishWorld = built.root.convert(position: built.finishPoint, to: nil)
        let vehicle = built.vehicle
        if var rc = vehicle.components[PhysicsRobotComponent.self] {
            rc.targetPosition = finishWorld
            rc.startPosition = vehicle.position(relativeTo: nil)
            vehicle.components.set(rc)
        }
        if var run = vehicle.components[CourseRunComponent.self] {
            run.finishPoint = finishWorld
            vehicle.components.set(run)
        }

        self.anchor = anchor
        self.course = built
        subscribeToContacts(vehicle: built.vehicle, scene: arView.scene)
        phase = .ready
    }

    // MARK: - Run

    /// "Go!": the vehicle already targets the finish; just start polling the outcome.
    func startRun() {
        guard course != nil else { return }
        feedback = nil
        phase = .running
        pollTimer = Timer.publish(every: 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.pollOutcome() }
    }

    private func pollOutcome() {
        guard let vehicle = course?.vehicle,
              let run = vehicle.components[CourseRunComponent.self],
              run.isResolved else { return }
        pollTimer?.cancel(); pollTimer = nil
        feedback = FeedbackEngine.feedback(for: run, config: config)
        phase = .finished
    }

    /// "Fix it for me": apply the suggestion, then rebuild for another attempt.
    func applySuggestionAndRetry() {
        if let change = feedback?.suggestedConfigChange {
            config = change(config)
        }
        buildCourse()
    }

    /// Retry with the current design unchanged.
    func retry() { buildCourse() }

    // MARK: - Contact classification

    /// Classifies each vehicle contact into the run telemetry. A body-vs-tunnel hit
    /// (obstacle carries an opening) counts as "too tall"; any other obstacle body
    /// contact counts as a chassis scrape.
    private func subscribeToContacts(vehicle: Entity, scene: RealityKit.Scene) {
        let began = scene.subscribe(to: CollisionEvents.Began.self, on: vehicle) { [weak self] event in
            // The subscribed entity isn't guaranteed to be entityA — pick the other side.
            let other = event.entityA.id == vehicle.id ? event.entityB : event.entityA
            self?.handleContact(vehicle: vehicle, other: other)
        }
        subscriptions.append(began)
    }

    private func handleContact(vehicle: Entity, other: Entity) {
        // The marker lives on the prop's parent, but the collider is its child box —
        // walk up from the contacted entity to find the obstacle it belongs to.
        guard let marker = marker(in: other),
              var run = vehicle.components[CourseRunComponent.self] else { return }
        if marker.openingHeight != nil {
            run.tunnelBlockedHits += 1
        } else {
            run.chassisHitCount += 1
        }
        vehicle.components.set(run)
    }

    /// First `ObstacleMarkerComponent` on `entity` or any of its ancestors.
    private func marker(in entity: Entity) -> ObstacleMarkerComponent? {
        var node: Entity? = entity
        while let current = node {
            if let m = current.components[ObstacleMarkerComponent.self] { return m }
            node = current.parent
        }
        return nil
    }

    // MARK: - Teardown

    func teardown() {
        pollTimer?.cancel(); pollTimer = nil
        subscriptions.forEach { $0.cancel() }
        subscriptions.removeAll()
        anchor?.removeFromParent()
        anchor = nil
        course = nil
    }
}

//
//  EnvironmentScanCoordinator.swift
//  ARTutorial
//
//  Drives the real-world scan mode across an explicit flow:
//
//    scanning → ready → navigating
//
//    • scanning   — RealityKit scene understanding reconstructs the environment
//                   (floor + objects) and turns it into physics colliders. The user
//                   pans to build the map, then taps "Process Scan".
//    • ready      — the first tap drops the robot onto the detected floor (→ navigating).
//    • navigating — taps set the robot's A→B destination on any real surface.
//
//  Plane-vs-object detection is done entirely by RealityKit's scene understanding
//  (no custom mesh/plane extraction). Step-over (< ¼ robot height) and fall physics
//  are owned by RobotControlSystem against those colliders.
//

import RealityKit
import ARKit
import UIKit
import Combine

enum ScanPhase: Equatable {
    case scanning   // accumulating the map; taps ignored
    case ready      // map built; tap to place the robot
    case navigating // robot placed; tap to set destination
}

final class EnvironmentScanCoordinator: ObservableObject {

    weak var arView: ARView?

    /// Drives the scan → process → place → navigate flow. SwiftUI binds the UI to this.
    @Published var phase: ScanPhase = .scanning

    private var robot: Entity?
    /// Anchor holding the spawn pad + robot, kept so "Re-scan" can remove it all.
    private var placementAnchor: AnchorEntity?

    init() {
        RobotControlSystem.bootstrap()
    }

    // MARK: - Flow

    /// "Process Scan": the environment is reconstructed live by scene understanding,
    /// so this simply gates the user into placement.
    func processScan() {
        phase = .ready
    }

    /// "Re-scan": clear the robot and return to scanning.
    func reset() {
        placementAnchor?.removeFromParent()
        placementAnchor = nil
        robot = nil
        phase = .scanning
    }

    // MARK: - Tap handling

    @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard let arView = recognizer.view as? ARView else { return }
        let location = recognizer.location(in: arView)

        switch phase {
        case .scanning:
            return // UI prompts the user to process the scan first
        case .ready:
            placeRobot(at: location, in: arView)
        case .navigating:
            sendRobot(to: location, in: arView)
        }
    }

    /// Tap while ready: drop the robot onto the detected floor.
    private func placeRobot(at location: CGPoint, in arView: ARView) {
        guard let result = arView.raycast(from: location,
                                          allowing: .estimatedPlane,
                                          alignment: .horizontal).first else {
            print("No surface found yet — keep moving the device to map the area.")
            return
        }

        let t = result.worldTransform.columns.3
        let hitPoint = SIMD3<Float>(t.x, t.y, t.z)
        let anchor = AnchorEntity(world: hitPoint)

        // Safety landing pad: a small static floor at the tapped point so the robot
        // always has something to land on while scene understanding finishes building
        // the surrounding collision. Kept small so the robot can walk off it onto the
        // real geometry — or off a real edge — a few centimetres away.
        anchor.addChild(makeLandingPad())

        let newRobot = PhysicsSceneFactory.makeRobot()
        newRobot.position = [0, 0.05, 0] // just above the pad; physics settles it
        anchor.addChild(newRobot)

        // Enable physics simulation for the robot (see PhysicsPlaygroundCoordinator).
        anchor.components.set(PhysicsSimulationComponent())

        arView.scene.addAnchor(anchor)
        placementAnchor = anchor

        // Record world spawn for off-map fall recovery.
        if var rc = newRobot.components[PhysicsRobotComponent.self] {
            rc.startPosition = SIMD3<Float>(hitPoint.x, hitPoint.y + 0.05, hitPoint.z)
            newRobot.components.set(rc)
        }

        robot = newRobot
        phase = .navigating
        print("Robot placed. Tap surfaces to send it around.")
    }

    /// A small translucent static pad that guarantees ground under the spawn point.
    private func makeLandingPad() -> ModelEntity {
        let size = SIMD3<Float>(0.2, 0.02, 0.2)
        let pad = ModelEntity(
            mesh: .generateBox(size: size),
            materials: [SimpleMaterial(color: UIColor.systemBlue.withAlphaComponent(0.25), isMetallic: false)]
        )
        pad.position = [0, -0.01, 0] // top face sits at the anchor origin (tapped point)
        let shape = ShapeResource.generateBox(size: size)
        pad.components.set(CollisionComponent(shapes: [shape]))
        pad.components.set(PhysicsBodyComponent(
            shapes: [shape],
            mass: 1,
            material: .generate(friction: 0.85, restitution: 0.0),
            mode: .static
        ))
        return pad
    }

    /// Tap while navigating: raycast the real world for a destination (B).
    /// Uses ARKit's raycast against planes + the reconstructed mesh (Apple's
    /// pattern), which is more robust than raycasting only against entities.
    private func sendRobot(to location: CGPoint, in arView: ARView) {
        guard let robot else { return }

        guard let result = arView.raycast(from: location,
                                          allowing: .estimatedPlane,
                                          alignment: .any).first else {
            print("Tap didn't hit any surface.")
            return
        }

        let t = result.worldTransform.columns.3
        let target = SIMD3<Float>(t.x, t.y, t.z)

        if var rc = robot.components[PhysicsRobotComponent.self] {
            rc.targetPosition = target
            robot.components.set(rc)
        }
    }
}

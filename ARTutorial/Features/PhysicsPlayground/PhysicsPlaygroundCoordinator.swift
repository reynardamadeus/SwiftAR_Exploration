//
//  PhysicsPlaygroundCoordinator.swift
//  ARTutorial
//
//  Bridges taps to the physics world. Keeps AR/session concerns out of the views.
//
//  Interaction model (tap-to-target, start + finish):
//    • First tap  → raycast the real world, drop the playground there. The robot's
//                   spawn point is its "start".
//    • Next taps  → raycast the RealityKit scene, use the hit point as the robot's
//                   "finish". The RobotControlSystem walks it there via physics.
//

import RealityKit
import ARKit

final class PhysicsPlaygroundCoordinator {

    weak var arView: ARView?

    private var playground: PhysicsPlayground?
    private var isPlaced = false

    init() {
        RobotControlSystem.bootstrap()
    }

    // MARK: - Tap handling

    @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard let arView = recognizer.view as? ARView else { return }
        let location = recognizer.location(in: arView)

        if isPlaced {
            sendRobot(to: location, in: arView)
        } else {
            placePlayground(at: location, in: arView)
        }
    }

    /// First tap: anchor the playground on a detected real-world surface.
    private func placePlayground(at location: CGPoint, in arView: ARView) {
        guard let result = arView.raycast(from: location,
                                          allowing: .estimatedPlane,
                                          alignment: .horizontal).first else {
            print("No real-world surface found to place the playground.")
            return
        }

        // Use only the position — keep the playground aligned with world-up so the
        // ramp/platform stay level regardless of the detected plane's orientation.
        let t = result.worldTransform.columns.3
        let anchor = AnchorEntity(world: SIMD3<Float>(t.x, t.y, t.z))

        let built = PhysicsSceneFactory.makePlayground()
        anchor.addChild(built.root)
        arView.scene.addAnchor(anchor)

        // Capture the robot's world spawn point so the control system can recover it
        // if it ever falls off the map.
        if var rc = built.robot.components[PhysicsRobotComponent.self] {
            rc.startPosition = built.robot.position(relativeTo: nil)
            built.robot.components.set(rc)
        }

        playground = built
        isPlaced = true
        print("Playground placed. Tap a surface to send the robot.")
    }

    /// Subsequent taps: raycast the scene and set the robot's target point.
    private func sendRobot(to location: CGPoint, in arView: ARView) {
        guard let playground else { return }
        guard let ray = arView.ray(through: location) else { return }

        let hits = arView.scene.raycast(origin: ray.origin,
                                        direction: ray.direction,
                                        length: 10,
                                        query: .nearest)

        // Ignore hits on the robot itself; any surface or pushable box is a valid goal.
        guard let hit = hits.first(where: { $0.entity != playground.robot }) else {
            print("Tap didn't hit a target surface.")
            return
        }

        if var robot = playground.robot.components[PhysicsRobotComponent.self] {
            robot.targetPosition = hit.position   // world space; only X/Z is used
            playground.robot.components.set(robot)
        }
    }
}

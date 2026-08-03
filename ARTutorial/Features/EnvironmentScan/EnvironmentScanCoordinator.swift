//
//  EnvironmentScanCoordinator.swift
//  ARTutorial
//
//  Drives the real-world scan mode: an `ARWorldMapper` turns the scanned scene into
//  land (planes) and obstacles (mesh), and the robot navigates that map.
//
//  Taps:
//    • First tap → place the robot on scanned land (raycast the real world).
//    • Next taps → set the robot's target on any mapped surface.
//

import RealityKit
import ARKit
import UIKit

final class EnvironmentScanCoordinator {

    weak var arView: ARView?

    /// Owns the session delegate that builds the physics map. Held strongly here
    /// because `ARSession.delegate` is weak.
    let mapper = ARWorldMapper()

    private var robot: Entity?

    init() {
        RobotControlSystem.bootstrap()
    }

    @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard let arView = recognizer.view as? ARView else { return }
        let location = recognizer.location(in: arView)

        if robot == nil {
            placeRobot(at: location, in: arView)
        } else {
            sendRobot(to: location, in: arView)
        }
    }

    /// First tap: drop the robot onto detected real-world land.
    private func placeRobot(at location: CGPoint, in arView: ARView) {
        guard let result = arView.raycast(from: location,
                                          allowing: .estimatedPlane,
                                          alignment: .horizontal).first else {
            print("No scanned surface found yet — keep moving the device to map the area.")
            return
        }

        let t = result.worldTransform.columns.3
        let hitPoint = SIMD3<Float>(t.x, t.y, t.z)
        let anchor = AnchorEntity(world: hitPoint)

        // Safety landing pad: a small static floor at the tapped point so the robot
        // always has something to land on during the moment before the scanned land
        // collision is built. Kept small so the robot can still walk off onto real
        // geometry — or off a real edge — a few centimetres away.
        anchor.addChild(makeLandingPad())

        let newRobot = PhysicsSceneFactory.makeRobot()
        newRobot.position = [0, 0.05, 0] // just above the pad; physics settles it
        anchor.addChild(newRobot)
        arView.scene.addAnchor(anchor)

        // Record world spawn for off-map fall recovery.
        if var rc = newRobot.components[PhysicsRobotComponent.self] {
            rc.startPosition = SIMD3<Float>(hitPoint.x, hitPoint.y + 0.05, hitPoint.z)
            newRobot.components.set(rc)
        }

        robot = newRobot
        print("Robot placed on the scanned land. Tap surfaces to send it around.")
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

    /// Subsequent taps: raycast the mapped scene for a target point.
    private func sendRobot(to location: CGPoint, in arView: ARView) {
        guard let robot, let ray = arView.ray(through: location) else { return }

        let hits = arView.scene.raycast(origin: ray.origin,
                                        direction: ray.direction,
                                        length: 15,
                                        query: .nearest)

        guard let hit = hits.first(where: { $0.entity.id != robot.id }) else {
            print("Tap didn't hit any mapped surface.")
            return
        }

        if var rc = robot.components[PhysicsRobotComponent.self] {
            rc.targetPosition = hit.position
            robot.components.set(rc)
        }
    }
}

//
//  RoboticsARView.swift
//  Hijauin
//
//  Created by Reynard Amadeus  on 06/08/26.
//
//  SwiftUI wrapper + ARView coordinator that wires the pieces together:
//
//    ARKit (LiDAR mesh + plane detection)
//        → TabletopObstacleDetector  (mesh → obstacle boxes)
//        → ObstacleEntityManager     (boxes → physics entities)
//
//  It also turns on RealityKit Scene Understanding physics so the robot
//  collides with the real environment for free.
//
//  Detection runs on a throttle (not every frame) on a background queue —
//  mesh clustering is too heavy for 60 fps.
//
//  Requires: iPad Pro with LiDAR. Info.plist must include NSCameraUsageDescription.
//
 
import SwiftUI
import RealityKit
import ARKit
 
// MARK: - SwiftUI entry point
 
struct RoboticsARView: UIViewRepresentable {
 
    func makeCoordinator() -> RoboticsARCoordinator { RoboticsARCoordinator() }
 
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
 
        // LiDAR scene reconstruction with semantic labels + horizontal planes.
        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        }
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        arView.session.run(config)
 
        // Let virtual entities collide with the real world mesh automatically.
        arView.environment.sceneUnderstanding.options.insert(.collision)
        arView.environment.sceneUnderstanding.options.insert(.physics)
 
        // --- Debug visualization (comment out for production) ---
        // Colored overlay of the live LiDAR mesh as it's scanned.
        arView.debugOptions.insert(.showSceneUnderstanding)
        // Wireframes of every collision shape + contact points. This is the
        // direct proof that the mesh and obstacle boxes are colliders.
        arView.debugOptions.insert(.showPhysics)
 
        context.coordinator.attach(to: arView)
        return arView
    }
 
    func updateUIView(_ uiView: ARView, context: Context) {}
}
 
// MARK: - Coordinator
 
final class RoboticsARCoordinator: NSObject, ARSessionDelegate {
 
    private weak var arView: ARView?
    private var obstacleManager: ObstacleEntityManager?
    private let detector = TabletopObstacleDetector()
 
    /// The table the robot drives on. Set once the user taps to place the model.
    private var tablePlane: TablePlane?
 
    /// Throttle: run detection at most this often.
    private let detectionInterval: TimeInterval = 0.5
    private var lastDetection: TimeInterval = 0
    private let workQueue = DispatchQueue(label: "obstacle.detection", qos: .userInitiated)
    private var isDetecting = false
 
    @MainActor
    func attach(to arView: ARView) {
        self.arView = arView
        arView.session.delegate = self
 
        // Obstacles are parented to a world anchor so they stay put.
        let anchor = AnchorEntity(world: .zero)
        arView.scene.addAnchor(anchor)
        self.obstacleManager = ObstacleEntityManager(root: anchor)
 
        // Tap to drop a physics ball — the visual proof that collision works.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tap)
    }
 
    /// Drops a dynamic sphere at the tapped point. Watch it fall and bounce
     /// off the obstacle boxes and the real-world LiDAR mesh.
     @MainActor
     @objc func handleTap(_ gesture: UITapGestureRecognizer) {
         guard let arView else { return }
         let screenPoint = gesture.location(in: arView)
  
         // Figure out where in the world the tap lands.
         let spawn: SIMD3<Float>
         if let hit = arView.raycast(from: screenPoint,
                                     allowing: .estimatedPlane,
                                     alignment: .any).first {
             // 20 cm above the surface we tapped, so it visibly drops.
             spawn = hit.worldTransform.position + SIMD3<Float>(0, 0.20, 0)
         } else {
             // Fallback: 25 cm in front of the camera (note: forward, not -forward).
             let camera = arView.cameraTransform
             spawn = camera.translation + camera.matrix.forward * 0.25
         }
  
         let radius: Float = 0.03
         let ball = ModelEntity(
             mesh: .generateSphere(radius: radius),
             materials: [SimpleMaterial(color: .systemRed, isMetallic: false)]
         )
         let shape = ShapeResource.generateSphere(radius: radius)
         ball.collision = CollisionComponent(shapes: [shape])
         ball.physicsBody = PhysicsBodyComponent(shapes: [shape], mass: 0.2, mode: .dynamic)
  
         let anchor = AnchorEntity(world: spawn)
         anchor.addChild(ball)
         arView.scene.addAnchor(anchor)
     }
 
    /// Call this from your placement gesture once the robot is placed on a plane.
    /// `planeAnchor` is the ARPlaneAnchor the robot was dropped onto.
    @MainActor
    func setTable(from planeAnchor: ARPlaneAnchor) {
        let t = planeAnchor.transform
        let worldCenter = t.transformPoint(planeAnchor.center)
        tablePlane = TablePlane(
            height: worldCenter.y,
            center: SIMD2(worldCenter.x, worldCenter.z),
            halfExtent: SIMD2(planeAnchor.planeExtent.width / 2,
                              planeAnchor.planeExtent.height / 2)
        )
    }
 
    // MARK: ARSessionDelegate
 
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let now = frame.timestamp
        guard now - lastDetection >= detectionInterval, !isDetecting,
              let plane = tablePlane else { return }
        lastDetection = now
 
        // Snapshot mesh anchors on the main actor, cluster off-thread.
        let meshAnchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
        guard !meshAnchors.isEmpty else { return }
 
        isDetecting = true
        let detector = self.detector
        workQueue.async { [weak self] in
            let obstacles = detector.detectObstacles(in: meshAnchors, on: plane)
            Task { @MainActor in
                self?.obstacleManager?.update(with: obstacles)
                self?.isDetecting = false
            }
        }
    }
}

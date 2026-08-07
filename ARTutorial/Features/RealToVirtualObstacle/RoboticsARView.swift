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
import Combine
// MARK: - SwiftUI entry point

final class BallTelemetry: ObservableObject {
    @Published var hasBall: Bool = false
    @Published var heightAboveSurface: Float = 0   // meters above the tapped surface
    @Published var isSettled: Bool = false         // true once it comes to rest
    @Published var hasTable: Bool = false          // true once a table plane is found

}

 
struct RoboticsARView: UIViewRepresentable {
    let telemetry: BallTelemetry
    func makeCoordinator() -> RoboticsARCoordinator { RoboticsARCoordinator(telemetry: telemetry) }
 
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
 
        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        }
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        arView.session.run(config)
 
        arView.environment.sceneUnderstanding.options.insert(.collision)
        arView.environment.sceneUnderstanding.options.insert(.physics)
 
        // --- Debug visualization (comment out for production) ---
        arView.debugOptions.insert(.showSceneUnderstanding)
        arView.debugOptions.insert(.showPhysics)
 
        context.coordinator.attach(to: arView)
        return arView
    }
 
    func updateUIView(_ uiView: ARView, context: Context) {}}
 
// MARK: - Coordinator
  
final class RoboticsARCoordinator: NSObject, ARSessionDelegate {
 
    private let telemetry: BallTelemetry
 
    private weak var arView: ARView?
    private var obstacleManager: ObstacleEntityManager?
    private let detector = TabletopObstacleDetector()
 
    /// The table the ball/robot rests on. Auto-detected from horizontal planes.
    private var tablePlane: TablePlane?
    /// Area of the best table plane seen so far (to keep picking the largest).
    private var bestTableArea: Float = 0
 
    // Detection throttle.
    private let detectionInterval: TimeInterval = 0.5
    private var lastDetection: TimeInterval = 0
    private let workQueue = DispatchQueue(label: "obstacle.detection", qos: .userInitiated)
    private var isDetecting = false
 
    // Single test ball + height tracking.
    private let ballRadius: Float = 0.03
    private var ball: ModelEntity?
    private var placedAnchor: AnchorEntity?
    private var ballGroundY: Float = 0     // fallback reference if no table yet
    private var lastHeight: Float?
    private var updateSub: Cancellable?
 
    init(telemetry: BallTelemetry) {
        self.telemetry = telemetry
    }
 
    @MainActor
    func attach(to arView: ARView) {
        self.arView = arView
        arView.session.delegate = self
 
        let anchor = AnchorEntity(world: .zero)
        arView.scene.addAnchor(anchor)
        self.obstacleManager = ObstacleEntityManager(root: anchor)
 
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tap)
 
        updateSub = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.trackBallHeight(deltaTime: Float(event.deltaTime))
        }
    }
 
    // MARK: Auto table-plane detection
 
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) { considerPlanes(anchors) }
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) { considerPlanes(anchors) }
 
    /// Adopt the largest horizontal plane (preferring ones ARKit labels a table)
    /// as the single height reference.
    private func considerPlanes(_ anchors: [ARAnchor]) {
        for plane in anchors.compactMap({ $0 as? ARPlaneAnchor })
        where plane.alignment == .horizontal {
            let area = plane.planeExtent.width * plane.planeExtent.height
            let isTable = plane.classification == .table
            // Take it if it's the biggest so far, or a table nearly as big.
            guard area > bestTableArea || (isTable && area > bestTableArea * 0.6) else { continue }
            bestTableArea = max(bestTableArea, area)
 
            let c = plane.transform.transformPoint(plane.center)
            let table = TablePlane(
                height: c.y,
                center: SIMD2(c.x, c.z),
                halfExtent: SIMD2(plane.planeExtent.width / 2, plane.planeExtent.height / 2)
            )
            tablePlane = table
            if !telemetry.hasTable { telemetry.hasTable = true }
        }
    }
 
    // MARK: Tap → single ball
 
    @MainActor
    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let arView else { return }
        let screenPoint = gesture.location(in: arView)
 
        // Prefer a hit on a REAL detected plane (accurate Y); fall back to an
        // estimated plane only if none exists yet.
        let hit = arView.raycast(from: screenPoint,
                                 allowing: .existingPlaneGeometry,
                                 alignment: .horizontal).first
            ?? arView.raycast(from: screenPoint,
                              allowing: .estimatedPlane,
                              alignment: .any).first
 
        let spawn: SIMD3<Float>
        if let hit {
            let p = hit.worldTransform.columns.3
            ballGroundY = p.y
            spawn = SIMD3(p.x, p.y + 0.20, p.z)   // 20 cm above the tapped point
        } else {
            let camera = arView.cameraTransform
            spawn = camera.translation + camera.matrix.forward * 0.25
            ballGroundY = spawn.y - 0.20
        }
 
        // Keep only one ball.
        if let old = placedAnchor {
            arView.scene.removeAnchor(old)
            placedAnchor = nil
            ball = nil
        }
 
        let newBall = ModelEntity(
            mesh: .generateSphere(radius: ballRadius),
            materials: [SimpleMaterial(color: .systemRed, isMetallic: false)]
        )
        let shape = ShapeResource.generateSphere(radius: ballRadius)
        newBall.collision = CollisionComponent(shapes: [shape])
        newBall.physicsBody = PhysicsBodyComponent(shapes: [shape], mass: 0.2, mode: .dynamic)
 
        let anchor = AnchorEntity(world: spawn)
        anchor.addChild(newBall)
        arView.scene.addAnchor(anchor)
 
        // Assign to properties (a local `let ball` previously shadowed these,
        // leaving self.ball nil so tracking never ran). Reset the tracker.
        self.ball = newBall
        self.placedAnchor = anchor
        self.lastHeight = nil
 
        telemetry.hasBall = true
        telemetry.isSettled = false
    }
 
    // MARK: Height tracking
 
    @MainActor
    private func trackBallHeight(deltaTime: Float) {
        guard let ball else { return }
 
        let worldY = ball.position(relativeTo: nil).y
        // Measure against the fixed table plane when we have it (no distance
        // drift); otherwise fall back to the tapped surface height.
        let reference = tablePlane?.height ?? ballGroundY
        let height = worldY - reference - ballRadius   // 0 when resting on the surface
 
        var speed: Float = 0
        if let last = lastHeight, deltaTime > 0 {
            speed = (worldY - last) / deltaTime
        }
        lastHeight = worldY
 
        telemetry.heightAboveSurface = height
        telemetry.isSettled = abs(speed) < 0.01 && height < 0.005
    }
 
    // MARK: ARSessionDelegate — obstacle detection
 
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let now = frame.timestamp
        guard now - lastDetection >= detectionInterval, !isDetecting,
              let plane = tablePlane else { return }
        lastDetection = now
 
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

//
//  RobotEditorContainerView.swift
//  ARTutorial
//
//  Self-contained RealityKit view for the robot editor. Two modes share the
//  same RobotBuilder tree:
//    - .editor3D: non-AR orbit scene (drag to rotate, pinch to zoom, tap a
//      wheel to select it).
//    - .ar: ARKit world tracking — tap a horizontal surface to place the robot.
//  Mirrors the existing UIViewRepresentable + Coordinator pattern but is fully
//  separate from the shared AR code (never starts a session unless in AR mode).
//

import SwiftUI
import RealityKit
import ARKit
import UIKit

enum EditorMode: Hashable { case editor3D, ar }

struct RobotEditorContainerView: UIViewRepresentable {
    var mode: EditorMode
    var config: RobotConfig
    var onSlotSelected: (WheelSlot) -> Void
    var onStatus: (String) -> Void

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        let coordinator = context.coordinator
        coordinator.arView = arView
        coordinator.onStatus = onStatus

        coordinator.builder.attach(to: arView.scene)
        coordinator.applyConfig(config, forceRebuild: true)

        // Swap primitive fallbacks for the real USDZ once they finish loading.
        AssetCache.shared.onLoaded = { [weak coordinator] in
            guard let config = coordinator?.lastConfig else { return }
            coordinator?.applyConfig(config, forceRebuild: true)
        }
        AssetCache.shared.preload()

        coordinator.switchMode(to: mode)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onStatus = onStatus
        coordinator.onSlotSelected = onSlotSelected
        if coordinator.currentMode != mode {
            coordinator.switchMode(to: mode)
        }
        coordinator.applyConfig(config, forceRebuild: false)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSlotSelected: onSlotSelected, onStatus: onStatus)
    }
}

// MARK: - Coordinator

extension RobotEditorContainerView {

    @MainActor
    final class Coordinator {
        let builder = RobotBuilder()
        weak var arView: ARView?
        var onSlotSelected: (WheelSlot) -> Void
        var onStatus: (String) -> Void

        var currentMode: EditorMode?

        // Orbit camera state.
        private var yaw: Float = 0.6
        private var pitch: Float = 0.7
        private var radius: Float = 3.0
        private let cameraRig = AnchorEntity(world: Transform.identity.matrix)
        private let camera = PerspectiveCamera()
        private var cameraRigInstalled = false

        var lastConfig: RobotConfig?

        init(onSlotSelected: @escaping (WheelSlot) -> Void,
             onStatus: @escaping (String) -> Void) {
            self.onSlotSelected = onSlotSelected
            self.onStatus = onStatus
        }

        // MARK: Mode switching

        func switchMode(to mode: EditorMode) {
            guard let arView = arView else { return }
            clearGestures()

            switch mode {
            case .editor3D:
                arView.cameraMode = .nonAR
                arView.environment.background = .color(.black)
                arView.session.pause()
                setupCameraRig()
                builder.root.isEnabled = true
                builder.resetToOrigin()
                installEditorGestures()
                updateCamera()
            case .ar:
                teardownCameraRig()
                // Mirror the existing AR model viewer: real camera + horizontal
                // plane detection (+ scene reconstruction where supported).
                let config = ARWorldTrackingConfiguration()
                config.planeDetection = [.horizontal]
                if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                    config.sceneReconstruction = .mesh
                }
                arView.cameraMode = .ar
                arView.session.run(config)
                builder.root.isEnabled = false // hidden until the user taps a flat surface
                builder.resetToOrigin()
                installARGesture()
                onStatus("Sentuh lantai / permukaan datar untuk meletakkan robot")
            }
            currentMode = mode
        }

        // MARK: Camera rig

        private func setupCameraRig() {
            guard !cameraRigInstalled, let arView = arView else { return }
            camera.camera.near = 0.01
            camera.camera.far = 100
            camera.camera.fieldOfViewInDegrees = 65
            cameraRig.position = [0, 0.4, 0]
            cameraRig.addChild(camera)
            arView.scene.addAnchor(cameraRig)
            cameraRigInstalled = true
        }

        private func teardownCameraRig() {
            guard cameraRigInstalled else { return }
            arView?.scene.removeAnchor(cameraRig)
            cameraRigInstalled = false
        }

        private func updateCamera() {
            // Camera is a child at +Z of the rig; rotating the rig orbits it,
            // and the wide pitch range lets you look down onto the top.
            let orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
                * simd_quatf(angle: pitch, axis: [1, 0, 0])
            cameraRig.orientation = orientation
            camera.position = [0, 0, radius]
        }

        // MARK: Gestures

        private func clearGestures() {
            arView?.gestureRecognizers?.removeAll()
        }

        private func installEditorGestures() {
            guard let arView = arView else { return }
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.maximumNumberOfTouches = 1
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleSelectTap(_:)))
            tap.require(toFail: pan)
            arView.addGestureRecognizer(pan)
            arView.addGestureRecognizer(pinch)
            arView.addGestureRecognizer(tap)
        }

        private func installARGesture() {
            guard let arView = arView else { return }
            let tap = UITapGestureRecognizer(target: self, action: #selector(handlePlaceTap(_:)))
            arView.addGestureRecognizer(tap)
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .changed else { return }
            let translation = gesture.translation(in: gesture.view)
            yaw += Float(translation.x) * 0.01
            pitch += Float(translation.y) * 0.01
            pitch = min(max(pitch, 0.08), .pi - 0.08) // allow full orbit incl. top-down
            gesture.setTranslation(.zero, in: gesture.view)
            updateCamera()
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard gesture.state == .changed else { return }
            radius /= Float(max(gesture.scale, 0.0001))
            radius = min(max(radius, 1.5), 6.0)
            gesture.scale = 1
            updateCamera()
        }

        @objc func handleSelectTap(_ gesture: UITapGestureRecognizer) {
            guard let arView = arView else { return }
            let location = gesture.location(in: arView)
            guard let hit = arView.entity(at: location) else { return }
            var current: Entity? = hit
            while let entity = current {
                if let slot = WheelSlot(rawValue: entity.name) {
                    onSlotSelected(slot)
                    return
                }
                current = entity.parent
            }
        }

        @objc func handlePlaceTap(_ gesture: UITapGestureRecognizer) {
            guard let arView = arView else { return }
            let location = gesture.location(in: arView)
            let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .horizontal)
            guard let result = results.first else {
                onStatus("Tidak ada permukaan terdeteksi — coba lagi")
                return
            }
            builder.place(at: result.worldTransform)
            builder.root.isEnabled = true
            onStatus("Robot diletakkan! Sentuh permukaan lain untuk memindahkan")
        }

        // MARK: Config diff

        func applyConfig(_ config: RobotConfig, forceRebuild: Bool) {
            var didChange = forceRebuild
            let bodyChanged = forceRebuild || lastConfig?.bodySize != config.bodySize
            let scaleChanged = forceRebuild || lastConfig?.wheelScale != config.wheelScale

            if bodyChanged {
                builder.applyBodySize(config.bodySize)
                didChange = true
            }

            for slot in WheelSlot.allCases {
                if forceRebuild || lastConfig?[slot].type != config[slot].type || scaleChanged {
                    builder.setWheel(type: config[slot].type, on: slot, scale: config.wheelScale)
                    didChange = true
                }
            }

            builder.updateCenterOfGravity(for: config)

            if didChange {
                builder.regenerateCollisions()
            }
            lastConfig = config
        }
    }
}

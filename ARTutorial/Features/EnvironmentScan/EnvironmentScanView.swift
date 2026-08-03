//
//  EnvironmentScanView.swift
//  ARTutorial
//
//  Real-world scan mode. Enables scene reconstruction with classification so the
//  ARWorldMapper can separate walkable land (planes) from obstacles (mesh).
//
//  Flow: scan → process → place → navigate. See EnvironmentScanCoordinator.
//

import SwiftUI
import RealityKit
import ARKit

/// Hosts the ARView and wires it to the shared coordinator.
struct EnvironmentScanARView: UIViewRepresentable {

    let coordinator: EnvironmentScanCoordinator

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        coordinator.arView = arView

        // Stop ARView from managing (and overriding) our configuration, otherwise
        // scene reconstruction / classification may never get enabled.
        arView.automaticallyConfigureSession = false

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]

        // Classification lets us tell floor (land) from objects (obstacles).
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }

        // RealityKit scene understanding is the single source of truth for the
        // environment: .physics turns the reconstructed mesh into colliders (the robot
        // walks on the floor and collides with obstacles), and .showSceneUnderstanding
        // renders that mesh — floor and objects alike. No custom plane/mesh extraction.
        arView.environment.sceneUnderstanding.options = [.physics]
        arView.debugOptions.insert(.showSceneUnderstanding)

        arView.session.run(config)

        let tap = UITapGestureRecognizer(
            target: coordinator,
            action: #selector(EnvironmentScanCoordinator.handleTap(_:))
        )
        arView.addGestureRecognizer(tap)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

struct EnvironmentScanScreenView: View {
    @StateObject private var coordinator = EnvironmentScanCoordinator()

    private var supportsMesh: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    var body: some View {
        ZStack {
            EnvironmentScanARView(coordinator: coordinator)
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 6) {
                statusBanner
                if !supportsMesh {
                    capabilityWarning
                }
                Spacer()
                bottomBar
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .navigationTitle("Environment Scan")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Overlays

    private var statusBanner: some View {
        Text(bannerText)
            .font(.footnote)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    }

    private var capabilityWarning: some View {
        Text("This device can't reconstruct the scene (no LiDAR) — only planes (land) will be detected, not obstacles. Use a LiDAR device for the full demo.")
            .font(.caption)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color.orange.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var bottomBar: some View {
        switch coordinator.phase {
        case .scanning:
            Button {
                coordinator.processScan()
            } label: {
                Text("Process Scan")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(.blue, in: Capsule())
            }
        case .navigating:
            Button {
                coordinator.reset()
            } label: {
                Label("Re-scan", systemImage: "arrow.counterclockwise")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.6), in: Capsule())
            }
        case .ready:
            EmptyView()
        }
    }

    // MARK: - Copy

    private var bannerText: String {
        switch coordinator.phase {
        case .scanning:
            return "Scan slowly to map the area — RealityKit reconstructs the floor and objects around you. Tap “Process Scan” when done."
        case .ready:
            return "Map ready. Tap a green area to place the robot."
        case .navigating:
            return "Tap anywhere to send the robot there. It steps over low objects and falls off ledges."
        }
    }
}

#Preview {
    NavigationStack { EnvironmentScanScreenView() }
}

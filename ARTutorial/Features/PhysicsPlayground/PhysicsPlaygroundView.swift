//
//  PhysicsPlaygroundView.swift
//  ARTutorial
//
//  SwiftUI surface for the physics PoC. UI only — all AR/physics logic lives in
//  the coordinator, factory and system.
//

import SwiftUI
import RealityKit
import ARKit

/// Hosts the ARView and forwards taps to `PhysicsPlaygroundCoordinator`.
struct PhysicsPlaygroundARView: UIViewRepresentable {

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        context.coordinator.arView = arView

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        arView.session.run(config)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(PhysicsPlaygroundCoordinator.handleTap(_:))
        )
        arView.addGestureRecognizer(tap)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> PhysicsPlaygroundCoordinator {
        PhysicsPlaygroundCoordinator()
    }
}

/// Full screen with a short instruction banner.
struct PhysicsPlaygroundScreenView: View {
    var body: some View {
        ZStack(alignment: .top) {
            PhysicsPlaygroundARView()
                .edgesIgnoringSafeArea(.all)

            Text("Tap a flat surface to place the playground, then tap the ground, ramp or platform to send the robot there.")
                .font(.footnote)
                .foregroundStyle(.white)
                .padding(10)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                .padding()
        }
        .navigationTitle("Physics Playground")
        .navigationBarTitleDisplayMode(.inline)
    }
}

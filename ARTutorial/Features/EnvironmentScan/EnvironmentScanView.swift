//
//  EnvironmentScanView.swift
//  ARTutorial
//
//  Real-world scan mode. Enables scene reconstruction with classification so the
//  ARWorldMapper can separate walkable land (planes) from obstacles (mesh).
//

import SwiftUI
import RealityKit
import ARKit

struct EnvironmentScanARView: UIViewRepresentable {

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        context.coordinator.arView = arView
        // The mapper needs the view to add mapped land/obstacle entities to the scene.
        context.coordinator.mapper.arView = arView

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

        // The mapper builds the physics world from session updates.
        arView.session.delegate = context.coordinator.mapper
        arView.session.run(config)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(EnvironmentScanCoordinator.handleTap(_:))
        )
        arView.addGestureRecognizer(tap)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> EnvironmentScanCoordinator {
        EnvironmentScanCoordinator()
    }
}

struct EnvironmentScanScreenView: View {
    var body: some View {
        ZStack(alignment: .top) {
            EnvironmentScanARView()
                .edgesIgnoringSafeArea(.all)

            Text("Scan slowly to map the area — green is land, red is obstacles. Tap the floor to drop the robot, then tap where it should go.")
                .font(.footnote)
                .foregroundStyle(.white)
                .padding(10)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                .padding()
        }
        .navigationTitle("Environment Scan")
        .navigationBarTitleDisplayMode(.inline)
    }
}

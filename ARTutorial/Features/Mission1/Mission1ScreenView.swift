//
//  Mission1ScreenView.swift
//  ARTutorial
//
//  SwiftUI screen for Mission 1 — "Tanjakan". Hosts the AR session and a thin
//  control overlay (Build → Start → result → Reset). All AR/physics logic lives in
//  `Mission1Coordinator`; this file only renders and forwards taps, keeping UI and
//  AR concerns separate per the project's architecture rules.
//

import SwiftUI
import RealityKit
import ARKit

struct Mission1ScreenView: View {
    @StateObject private var coordinator = Mission1Coordinator()

    var body: some View {
        ZStack(alignment: .bottom) {
            Mission1ARViewContainer(coordinator: coordinator)
                .ignoresSafeArea()

            controls
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .padding()
        }
    }

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 12) {
            Text(statusText)
                .font(.headline)
                .multilineTextAlignment(.center)

            switch coordinator.phase {
            case .placing:
                Button("Bangun Tanjakan") { coordinator.buildScene() }
                    .buttonStyle(.borderedProminent)
            case .ready:
                Button("Mulai") { coordinator.startRun() }
                    .buttonStyle(.borderedProminent)
            case .running:
                ProgressView()
            case .finished:
                Button("Ulangi") { coordinator.reset() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var statusText: String {
        switch coordinator.phase {
        case .placing:
            return "Arahkan kamera ke permukaan datar, lalu bangun tanjakan."
        case .ready:
            return "Tekan Mulai untuk menjalankan mobil ke atas tanjakan."
        case .running:
            return "Mobil sedang menanjak…"
        case .finished:
            switch coordinator.outcome {
            case .success: return "Berhasil! Mobil naik ke atas tanjakan dan tetap tegak. 🎉"
            case .flipped: return "Gagal — mobil terbalik (roda tidak menyentuh) selama 3 detik."
            case .running, .none: return "Selesai."
            }
        }
    }
}

/// Bridges an `ARView` (horizontal-plane world tracking) into SwiftUI and hands it
/// to the coordinator. Mirrors the AR setup in `ARContainerView`, minus the sample
/// model-loading path.
struct Mission1ARViewContainer: UIViewRepresentable {
    let coordinator: Mission1Coordinator

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        arView.session.run(config)

        coordinator.arView = arView
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

#Preview {
    Mission1ScreenView()
}

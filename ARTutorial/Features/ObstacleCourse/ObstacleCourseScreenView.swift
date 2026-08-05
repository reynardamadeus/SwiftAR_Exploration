//
//  ObstacleCourseScreenView.swift
//  ARTutorial
//
//  SwiftUI shell for the obstacle-course mode. Keeps only presentation here; all
//  AR/physics logic lives in `ObstacleCourseCoordinator`. The overlay changes with
//  `coordinator.phase`, walking the child through:
//  scan → confirm → build → go → feedback → (fix it) → retry.
//
//  Wire it into `HomeView` with:
//      NavigationLink(destination: ObstacleCourseScreenView()) { Text("Obstacle Course") }
//

import SwiftUI
import RealityKit
import ARKit

struct ObstacleCourseScreenView: View {
    @StateObject private var coordinator = ObstacleCourseCoordinator()

    var body: some View {
        ZStack(alignment: .bottom) {
            CourseARViewContainer(coordinator: coordinator)
                .ignoresSafeArea()

            controls
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .padding()
        }
        .sheet(item: $coordinator.feedback) { feedback in
            FeedbackSheet(feedback: feedback, coordinator: coordinator)
                .presentationDetents([.medium])
        }
        .navigationTitle("Obstacle Course")
    }

    @ViewBuilder
    private var controls: some View {
        switch coordinator.phase {
        case .scanning:
            VStack(spacing: 8) {
                Text("Arahkan kamera ke rintanganmu").font(.headline)
                Button("Scan Rintangan") { coordinator.scan() }
                    .buttonStyle(.borderedProminent)
            }

        case .confirming:
            VStack(spacing: 10) {
                Text("Ini rintanganmu?").font(.headline)
                ForEach(coordinator.detections) { d in
                    ObstacleChipRow(detection: d) { kind in
                        coordinator.relabel(d.id, to: kind)
                    }
                }
                Button("Bangun Lintasan") { coordinator.buildCourse() }
                    .buttonStyle(.borderedProminent)
            }

        case .ready:
            Button("Go! 🚗") { coordinator.startRun() }
                .buttonStyle(.borderedProminent)
                .font(.title2)

        case .running:
            Label("Mobil sedang jalan…", systemImage: "car.fill")
                .font(.headline)

        case .finished:
            Text("Selesai!").font(.headline)
        }
    }
}

/// One detected region with tappable category chips (the human-in-the-loop step).
private struct ObstacleChipRow: View {
    let detection: DetectedObstacle
    let onSelect: (ObstacleKind) -> Void

    var body: some View {
        HStack {
            ForEach(ObstacleKind.allCases, id: \.self) { kind in
                Button(kind.displayName) { onSelect(kind) }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .tint(detection.kind == kind ? .blue : .gray)
            }
        }
    }
}

/// Feedback sheet with a "Fix it for me" shortcut into the redesign loop.
private struct FeedbackSheet: View {
    let feedback: EngineeringFeedback
    let coordinator: ObstacleCourseCoordinator

    var body: some View {
        VStack(spacing: 20) {
            Text(feedback.isSuccess ? "🎉" : "🔧").font(.system(size: 60))
            Text(feedback.childMessage)
                .font(.title3).multilineTextAlignment(.center)

            if feedback.isSuccess {
                Button("Main Lagi") { coordinator.retry() }
                    .buttonStyle(.borderedProminent)
            } else {
                HStack {
                    Button("Coba Lagi") { coordinator.retry() }
                        .buttonStyle(.bordered)
                    Button("Perbaiki Untukku") { coordinator.applySuggestionAndRetry() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
    }
}

/// Minimal ARView host configured for horizontal-plane raycasting. Scene
/// reconstruction can be enabled on LiDAR devices for real obstacle heights.
struct CourseARViewContainer: UIViewRepresentable {
    let coordinator: ObstacleCourseCoordinator

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh // optional: enables real height sampling
        }
        arView.session.run(config)
        coordinator.arView = arView
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

//
//  BridgeMissionView.swift
//  ARTutorial
//
//  "Misi: Menyeberang Jembatan" screen.
//
//  Flow (the user places everything, then a button drives the car):
//    1. Tap floor → place point A (a green marker).
//    2. Tap floor → place point B (a red marker). The app measures A→B and checks
//       it against the 30 cm Panjang constraint (Lebar 5 cm / Tinggi 10 cm are fixed).
//    3. "Bangun Jembatan" → a block at A, a block at B, and an elevated beam between
//       them (gap underneath). The editor's car is placed on block A, facing B.
//    4. "Mulai" → the car drives the straight line A→B. It can fall into the gap.
//    5. The system reports success / fail-flipped / fail-stuck via MissionState.
//

import SwiftUI
import RealityKit
import ARKit
import UIKit
import Combine

struct BridgeMissionARView: UIViewRepresentable {
    let coordinator: BridgeMissionCoordinator

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        coordinator.arView = arView

        arView.automaticallyConfigureSession = false
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        arView.environment.background = .cameraFeed(exposureCompensation: 0)
        arView.session.run(config)

        let tap = UITapGestureRecognizer(target: coordinator,
                                         action: #selector(BridgeMissionCoordinator.handleTap(_:)))
        arView.addGestureRecognizer(tap)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

final class BridgeMissionCoordinator: ObservableObject {

    weak var arView: ARView?

    private var A: SIMD3<Float>?
    private var B: SIMD3<Float>?
    private var anchor: AnchorEntity?
    private var car: Entity?
    private var markers: [AnchorEntity] = []

    init() {
        BridgeMissionSystem.bootstrap()
    }

    // MARK: - Tap routing (only places A and B)

    @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard let arView = recognizer.view as? ARView else { return }
        let location = recognizer.location(in: arView)

        switch MissionState.shared.status {
        case .placeA: placeEndpoint(at: location, in: arView, isA: true)
        case .placeB: placeEndpoint(at: location, in: arView, isA: false)
        default: break
        }
    }

    private func placeEndpoint(at location: CGPoint, in arView: ARView, isA: Bool) {
        guard let result = arView.raycast(from: location,
                                          allowing: .estimatedPlane,
                                          alignment: .horizontal).first else {
            MissionState.shared.message = "Tidak ada permukaan — coba lagi"
            return
        }
        let p = result.worldTransform.columns.3
        let point = SIMD3<Float>(p.x, p.y, p.z)

        if isA {
            A = point
            addMarker(at: point, color: .systemGreen)
            MissionState.shared.status = .placeB
            MissionState.shared.message = "Titik A siap. Sentuh lantai untuk titik B"
        } else {
            B = point
            addMarker(at: point, color: .systemRed)
            validateSpan()
        }
    }

    /// Measure A→B and check it against the 30 cm Panjang constraint.
    private func validateSpan() {
        guard let A, let B else { return }
        let span = simd_length(SIMD2<Float>(B.x - A.x, B.z - A.z))
        let ok = abs(span - BridgeMissionScene.targetLength) <= BridgeMissionScene.lengthTolerance
        let cm = Int(span * 100)
        MissionState.shared.spanMeters = span
        MissionState.shared.spanOK = ok
        MissionState.shared.status = .design
        MissionState.shared.message = ok
            ? "Panjang A→B \(cm) cm ✅. Sekarang buat mobilmu!"
            : "Panjang A→B \(cm) cm ❌ (target 30 cm). Tetap buat mobilmu untuk mencoba."
    }

    // MARK: - Build the bridge + car

    func buildBridge() {
        guard let arView, let A, let B else { return }

        let anchor = AnchorEntity(world: SIMD3<Float>(repeating: 0)) // world-coord children
        anchor.components.set(PhysicsSimulationComponent())

        let span = simd_length(SIMD2<Float>(B.x - A.x, B.z - A.z))
        let dir = simd_normalize(SIMD3<Float>(B.x - A.x, 0, B.z - A.z))

        // Bridge is built in a local frame (origin at A, +X toward B): place it at A
        // and yaw so +X aligns with A→B.
        let bridgeRoot = BridgeMissionScene.makeBridge(length: span,
                                                       width: MissionState.shared.bridgeWidthMeters)
        bridgeRoot.position = A
        bridgeRoot.orientation = simd_quatf(from: SIMD3<Float>(1, 0, 0), to: dir)
        anchor.addChild(bridgeRoot)

        // Car starts at A on the GROUND (base of the ramp), facing up toward B.
        let config = RobotGarage.shared.config
        let car = BridgeMissionScene.makeCar(from: config)
        car.position = SIMD3<Float>(A.x, BridgeMissionScene.carHalfHeight(from: config), A.z)
        // Face the car's +X toward B, then yaw 90° so it sits straight. Flip the sign
        // (or axis) here if it still points the wrong way.
        let faceB = simd_quatf(from: SIMD3<Float>(1, 0, 0), to: dir)
        car.orientation = faceB * simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
        anchor.addChild(car)

        arView.scene.addAnchor(anchor)
        self.anchor = anchor
        self.car = car

        MissionState.shared.status = .armed
        MissionState.shared.message = "Jembatan siap. Tekan Mulai untuk menjalankan mobil A→B"
    }

    // MARK: - Drive

    func start() {
        guard let car, let B else { return }
        if var mission = car.components[BridgeMissionComponent.self] {
            mission.targetB = B
            car.components.set(mission)
        }
        MissionState.shared.message = "Mobil melaju menuju B…"
    }

    // MARK: - Reset

    func reset() {
        anchor?.removeFromParent()
        anchor = nil
        car = nil
        A = nil
        B = nil
        for m in markers { m.removeFromParent() }
        markers.removeAll()
        MissionState.shared.reset()
    }

    // MARK: - Markers

    private func addMarker(at world: SIMD3<Float>, color: UIColor) {
        guard let arView else { return }
        let sphere = ModelEntity(mesh: .generateSphere(radius: 0.012),
                                 materials: [SimpleMaterial(color: color, isMetallic: false)])
        let a = AnchorEntity(world: world)
        a.addChild(sphere)
        arView.scene.addAnchor(a)
        markers.append(a)
    }
}

// MARK: - Screen

struct BridgeMissionScreenView: View {
    @StateObject private var coordinator = BridgeMissionCoordinator()
    @ObservedObject private var state = MissionState.shared
    @State private var showingEditor = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            BridgeMissionARView(coordinator: coordinator)
                .ignoresSafeArea()

            // Reset (always available).
            Button {
                coordinator.reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.6), in: Circle())
            }
            .padding()

            // Bottom controls.
            VStack {
                Spacer()
                controls
                    .padding(.horizontal)
                    .padding(.bottom, 12)
            }
        }
        .navigationTitle("Misi: Jembatan")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Randomize the bridge Lebar each time the mission opens.
            state.bridgeWidthMeters = Float.random(in: BridgeMissionScene.bridgeWidthMin...BridgeMissionScene.bridgeWidthMax)
        }
        .onDisappear { coordinator.reset() }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                RobotEditorView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Selesai") { showingEditor = false }
                        }
                    }
            }
        }
        .onChange(of: showingEditor) { _, isShown in
            if !isShown, state.status == .design {
                state.status = .ready
                state.message = "Mobil siap. Tekan Bangun Jembatan"
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 8) {
            statusBanner
            if state.status == .design || state.status == .ready { validationReadout }
            if state.status == .armed || state.status == .driving
                || state.status == .success || state.status == .failFlipped
                || state.status == .failStuck {
                runReadout
            }
            actionButton
        }
    }

    private var statusBanner: some View {
        Text(state.message)
            .font(.footnote)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(bannerColor.opacity(0.9), in: RoundedRectangle(cornerRadius: 10))
    }

    private var validationReadout: some View {
        HStack(spacing: 10) {
            Label(String(format: "%.0f cm", state.spanMeters * 100),
                  systemImage: state.spanOK ? "checkmark.circle.fill" : "xmark.circle.fill")
            Text("Panjang (30 cm)")
            Divider().background(.white.opacity(0.4))
            Text(String(format: "Lebar %.0f cm", state.bridgeWidthMeters * 100))
            Text("· Tinggi 10 cm")
        }
        .font(.caption.bold())
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.55), in: Capsule())
    }

    private var runReadout: some View {
        HStack(spacing: 16) {
            Label(String(format: "%.0f cm", state.distanceMeters * 100), systemImage: "ruler")
            Label("\(state.wheelsOnBridge)/4 roda", systemImage: "car.2")
        }
        .font(.caption.bold())
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.55), in: Capsule())
    }

    @ViewBuilder
    private var actionButton: some View {
        switch state.status {
        case .design:
            primaryButton("Buat Mobil", icon: "car.fill", color: .indigo) { showingEditor = true }
        case .ready:
            primaryButton("Bangun Jembatan", icon: "hammer", color: .brown) { coordinator.buildBridge() }
        case .armed:
            primaryButton("Mulai (A → B)", icon: "play.fill", color: .blue) { coordinator.start() }
        case .success, .failFlipped, .failStuck:
            primaryButton("Ulangi", icon: "arrow.counterclockwise", color: .gray) { coordinator.reset() }
        default:
            EmptyView() // placing A/B or driving — no button
        }
    }

    private func primaryButton(_ title: String, icon: String, color: Color,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(color, in: Capsule())
        }
    }

    private var bannerColor: Color {
        switch state.status {
        case .success: return .green
        case .failFlipped, .failStuck: return .red
        default: return .black
        }
    }
}

#Preview {
    NavigationStack { BridgeMissionScreenView() }
}

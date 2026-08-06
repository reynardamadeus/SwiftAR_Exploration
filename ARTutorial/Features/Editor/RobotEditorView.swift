//
//  RobotEditorView.swift
//  ARTutorial
//
//  The robot editor screen. Owns `RobotConfig` as the single source of truth.
//  The mode selector (2D / 3D / AR) lives at the BOTTOM in the same panel as
//  the sliders — thumb-reachable and clear of the top safe area. 2D shows the
//  schematic centered full-screen (3D hidden); 3D is the orbit editor; AR
//  places the robot in the real world.
//

import SwiftUI

enum ViewMode: Hashable { case twoD, threeD, ar }

struct RobotEditorView: View {
    @State private var config: RobotConfig = .default
    @State private var selectedSlot: WheelSlot?
    @State private var viewMode: ViewMode = .threeD
    @State private var status: String = ""

    // PRD §4.5 ranges.
    private let lengthRange: ClosedRange<Float> = 0.5...2.0 // Panjang (X)
    private let widthRange: ClosedRange<Float>  = 0.3...1.5 // Lebar   (Z)
    private let heightRange: ClosedRange<Float> = 0.2...1.0 // Tinggi  (Y)
    private let wheelScaleRange: ClosedRange<Float> = 0.01...2.5 // Ukuran Roda

    private var containerMode: EditorMode { viewMode == .ar ? .ar : .editor3D }

    var body: some View {
        Group {
            if viewMode == .twoD {
                // 2D editor centered, full-screen; the 3D editor is hidden.
                RobotSchematicView(config: config, selectedSlot: selectedSlot) { selectedSlot = $0 }
                    .background(Color(uiColor: .systemBackground))
                    .safeAreaInset(edge: .bottom, spacing: 0) { bottomPanel }
            } else {
                // 3D editor or AR. GeometryReader lets us lift the panel by the
                // exact bottom safe-area inset while the scene stays full-bleed.
                GeometryReader { geo in
                    ZStack(alignment: .bottom) {
                        RobotEditorContainerView(
                            mode: containerMode,
                            config: config,
                            onSlotSelected: { selectedSlot = $0 },
                            onStatus: { status = $0 }
                        )
                        .ignoresSafeArea()

                        if !status.isEmpty {
                            VStack {
                                statusBanner
                                    .padding(.top, max(geo.safeAreaInsets.top, 6))
                                Spacer()
                            }
                            .allowsHitTesting(false)
                        }

                        bottomPanel
                            .padding(.bottom, geo.safeAreaInsets.bottom)
                    }
                }
            }
        }
        .navigationTitle("Editor Robot")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewMode) { _, newMode in
            if newMode != .ar { status = "" }
        }
        .onChange(of: config) { _, newConfig in
            RobotGarage.shared.config = newConfig
        }
    }

    // MARK: Bottom panel (mode selector + controls)

    private var bottomPanel: some View {
        VStack(spacing: 10) {
            modeSelector
            if let slot = selectedSlot { wheelPicker(for: slot) }
            cogReadout
            VStack(spacing: 10) {
                sliderRow(label: "Panjang", value: $config.bodySize.length, range: lengthRange)
                sliderRow(label: "Lebar",   value: $config.bodySize.width,  range: widthRange)
                sliderRow(label: "Tinggi",  value: $config.bodySize.height, range: heightRange)
                sliderRow(label: "Roda",    value: $config.wheelScale,      range: wheelScaleRange)
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 24) 
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.6))
    }

    private var modeSelector: some View {
        Picker("Mode", selection: $viewMode) {
            Text("2D").tag(ViewMode.twoD)
            Text("3D").tag(ViewMode.threeD)
            Text("AR").tag(ViewMode.ar)
        }
        .pickerStyle(.segmented)
    }

    private func sliderRow(label: String, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
        HStack {
            Text(label).foregroundStyle(.white).frame(width: 60, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: "%.2f", value.wrappedValue))
                .foregroundStyle(.white)
                .monospacedDigit()
                .frame(width: 44)
        }
    }

    private func wheelPicker(for slot: WheelSlot) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("Roda \(slot.displayName)").font(.headline).foregroundStyle(.white)
                Spacer()
                Button("Selesai") { selectedSlot = nil }
                    .font(.subheadline.bold()).foregroundStyle(.yellow)
            }
            HStack(spacing: 10) {
                ForEach(RobotConfig.WheelType.allCases, id: \.self) { type in
                    Button {
                        config[slot].type = type
                    } label: {
                        Text(type.displayName)
                            .font(.subheadline.bold())
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(
                                config[slot].type == type ? Color.yellow : Color.white.opacity(0.2),
                                in: Capsule()
                            )
                            .foregroundStyle(config[slot].type == type ? .black : .white)
                    }
                }
            }
        }
    }

    // MARK: Status & CoG readout

    private var statusBanner: some View {
        Text(status)
            .font(.caption)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.white.opacity(0.85), in: Capsule())
            .foregroundStyle(.black)
            .padding(.horizontal)
    }

    private var cogReadout: some View {
        let cog = config.centerOfGravity()
        return HStack(spacing: 6) {
            Image(systemName: "scope").foregroundStyle(.red)
            Text(String(format: "Pusat Berat:  X %.2f   Y %.2f   Z %.2f", cog.x, cog.y, cog.z))
                .font(.caption2).foregroundStyle(.white).monospacedDigit()
            Spacer()
        }
    }
}

#Preview {
    NavigationStack { RobotEditorView() }
}

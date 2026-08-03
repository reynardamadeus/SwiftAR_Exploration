//
//  RobotSchematicView.swift
//  ARTutorial
//
//  Live, read-only top-down (2D) schematic of the robot. Mirrors the 3D config:
//  body rectangle, four wheel circles at the corners (hollow dashed ring when a
//  slot is empty), and the red center-of-gravity dot. Tap a wheel to select it.
//  Shown side-by-side with the 3D in landscape, or as a thumbnail in portrait.
//

import SwiftUI

struct RobotSchematicView: View {
    var config: RobotConfig
    var selectedSlot: WheelSlot?
    var onSelect: (WheelSlot) -> Void

    var body: some View {
        GeometryReader { proxy in
            let pad: CGFloat = 30
            let availW = max(proxy.size.width - 2 * pad, 1)
            let availH = max(proxy.size.height - 2 * pad, 1)
            let scale = min(availW / CGFloat(config.bodySize.length),
                            availH / CGFloat(config.bodySize.width))
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let halfLen = CGFloat(config.bodySize.length) / 2 * scale
            let halfWid = CGFloat(config.bodySize.width) / 2 * scale
            let wheelSize = max(0.22 * scale * CGFloat(config.wheelScale), 16)

            ZStack {
                Color.gray.opacity(0.07)

                // Body (top-down: length × width).
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.blue.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.blue, lineWidth: 2)
                    )
                    .frame(width: halfLen * 2, height: halfWid * 2)
                    .position(center)

                // Center of gravity (project X,Z to the plane).
                let cog = config.centerOfGravity()
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                    .position(x: center.x + CGFloat(cog.x) * scale,
                              y: center.y + CGFloat(cog.z) * scale)

                // Four wheels at the corners; tap to select.
                ForEach(WheelSlot.allCases, id: \.self) { slot in
                    wheelSymbol(for: config[slot].type, selected: selectedSlot == slot)
                        .frame(width: wheelSize, height: wheelSize)
                        .position(cornerPoint(slot, center: center, halfLen: halfLen, halfWid: halfWid))
                        .onTapGesture { onSelect(slot) }
                }

                // Front indicator (front = +X = right in this top-down view).
                VStack(spacing: 2) {
                    Image(systemName: "arrow.right").font(.title3.weight(.bold))
                    Text("Depan").font(.caption2)
                }
                .foregroundStyle(.green)
                .position(x: center.x + halfLen + 22, y: center.y)

                // Box dimensions in meters.
                VStack(spacing: 2) {
                    Text(String(format: "Panjang  %.2f m", config.bodySize.length))
                    Text(String(format: "Lebar  %.2f m", config.bodySize.width))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .position(x: center.x, y: center.y + halfWid + 20)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Map a slot to its screen corner. front = +X → right; right = +Z → down.
    private func cornerPoint(_ slot: WheelSlot, center: CGPoint,
                             halfLen: CGFloat, halfWid: CGFloat) -> CGPoint {
        let sx: CGFloat = (slot == .frontLeft || slot == .frontRight) ? 1 : -1
        let sz: CGFloat = (slot == .frontRight || slot == .rearRight) ? 1 : -1
        return CGPoint(x: center.x + sx * halfLen, y: center.y + sz * halfWid)
    }

    @ViewBuilder
    private func wheelSymbol(for type: RobotConfig.WheelType, selected: Bool) -> some View {
        let rim = Circle().stroke(selected ? Color.yellow : Color.black,
                                  lineWidth: selected ? 4 : 2)
        switch type {
        case .none:
            // Dashed hollow ring → "garis putus-putus" placeholder.
            Circle()
                .strokeBorder(Color.gray, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                .background(Circle().fill(Color.gray.opacity(0.1)))
        case .smooth:
            Circle().fill(Color(white: 0.7)).overlay(rim)
        case .offroad:
            Circle().fill(Color.brown).overlay(rim)
        case .heavy:
            Circle().fill(Color(white: 0.25)).overlay(rim)
        }
    }
}

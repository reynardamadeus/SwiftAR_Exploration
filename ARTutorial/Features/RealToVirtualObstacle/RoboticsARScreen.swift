//
//  RoboticsARScreen.swift
//  Hijauin
//
//  Created by Reynard Amadeus  on 06/08/26.
//
import SwiftUI
struct RoboticsARScreen: View {
    @StateObject private var telemetry = BallTelemetry()
 
    var body: some View {
        ZStack(alignment: .bottom) {
            RoboticsARView(telemetry: telemetry)
                .ignoresSafeArea()
 
            if telemetry.hasBall {
                readout
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 16)
            }
        }
    }
 
    private var readout: some View {
        VStack(spacing: 2) {
            Text(String(format: "Height: %.1f cm", telemetry.heightAboveSurface * 100))
                .font(.headline.monospacedDigit())
            if telemetry.isSettled {
                Text("● settled").font(.caption).foregroundStyle(.green)
            }
        }
    }
}
 

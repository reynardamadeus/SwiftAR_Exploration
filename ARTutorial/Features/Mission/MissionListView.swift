//
//  MissionListView.swift
//  ARTutorial
//
//  Entry point for mission-based play. Lists the available missions; selecting one
//  opens its flow. Currently one mission: Bridge Crossing.
//

import SwiftUI

struct MissionListView: View {
    var body: some View {
        List {
            Section("Misi yang Tersedia") {
                NavigationLink {
                    BridgeMissionScreenView()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Menyeberang Jembatan")
                            .font(.headline)
                        Text("Bangun mobil yang bisa menyeberang jembatan sempit di ketinggian 10 cm.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Misi")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { MissionListView() }
}

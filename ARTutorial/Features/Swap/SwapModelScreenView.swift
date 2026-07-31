//
//  ARScreenView.swift
//  ARTutorial
//
//  Created by Reynard Amadeus  on 30/07/26.
//

import ARKit
import SwiftUI

struct SwapModelScreenView: View {
    let modelNames = ["frame_truck", "Truck"]
    @State private var currentIndex = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            ARContainerView(
                entityName: modelNames[currentIndex],
                enableGesture: true
            )
            .edgesIgnoringSafeArea(.all)

            HStack {
                Button("Previous") {
                    currentIndex = (currentIndex - 1 + modelNames.count) % modelNames.count
                }
                Spacer()
                Text("Step \(currentIndex + 1)")
                    .foregroundColor(.white)
                Spacer()
                Button("Next") {
                    currentIndex = (currentIndex + 1) % modelNames.count
                }
            }
            .padding()
            .background(.black.opacity(0.5))
        }
    }
}

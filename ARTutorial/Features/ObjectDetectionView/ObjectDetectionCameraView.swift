//
//  ObjectDetectionCameraV.swift
//  ARTutorial
//
//  Created by Reynard Amadeus  on 03/08/26.
//
import SwiftUI
import ARKit
import RealityKit
struct ObjectDetectionCameraView: UIViewRepresentable {
    func updateUIView(_ uiView: ARView, context: Context) {
    }
    
    func makeUIView(context: Context) -> ARView {
        
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            configuration.sceneReconstruction = .meshWithClassification
        }
        
        arView.debugOptions.insert(.showSceneUnderstanding)
        
        arView.session.delegate = context.coordinator
        context.coordinator.aRView = arView
        arView.session.run(configuration)
        return arView
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(entityName: "object", enableGesture: false)
    }
    
}


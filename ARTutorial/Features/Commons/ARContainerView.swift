//
//  ARContainerView.swift
//  ARTutorial
//
//  Created by Reynard Amadeus  on 27/07/26.
//

import SwiftUI
import RealityKit
import ARKit

struct ARContainerView: UIViewRepresentable {
    var entityName: String
    var enableGesture: Bool
    func makeUIView(context: Context) -> ARView {
        //display AR Content
        let aRView = ARView(frame: .zero)
        context.coordinator.aRView = aRView
        //allow to look for flat surfaces
        let config = ARWorldTrackingConfiguration()
        
        //detect horizontal surface
        config.planeDetection = [.horizontal]
        
        
        //support 3D mesh construction of the environment (simply, to interact better with real life objects
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        
        aRView.session.run(config)
        if(enableGesture){
            let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
            aRView.addGestureRecognizer(tapGesture)
            
//            let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
//            aRView.addGestureRecognizer(pinchGesture)
        }else{
            //load 3D model
            guard let modelEntity = try? ModelEntity.loadModel(named: entityName) else{
                print("failed to load model")
                return aRView
            }
            // scale the 3D model
            modelEntity.scale = [0.01, 0.01, 0.01]
            modelEntity.generateCollisionShapes(recursive: true)
            //create the anchor
            //what is anchor? pretty much the plane/surface in your camera where you want to interact with the AR model
            let anchorEntity = AnchorEntity(plane: .horizontal)
            
            //establish the anchor and fill it with the 3D Model
            anchorEntity.addChild(modelEntity)
            aRView.scene.addAnchor(anchorEntity)
        
        }
          
        return aRView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.updateModel(named: entityName)

    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(entityName: entityName, enableGesture: enableGesture)
    }
    

}

//
//  Coordinator.swift
//  ARTutorial
//
//  Created by Reynard Amadeus  on 28/07/26.
//
import RealityKit
import ARKit

class Coordinator {
    var entityName: String
    var enableGesture: Bool
    weak var aRView: ARView?
    var placedAnchor: AnchorEntity?
    var placedTransform: simd_float4x4?
    var selectedEntity: ModelEntity?
    var initialScale: SIMD3<Float> = [0.01, 0.01, 0.01]

    init(entityName: String, enableGesture: Bool) {
        self.entityName = entityName
        self.enableGesture = enableGesture
    }
    //change moddel
    func updateModel(named newName: String) {
           guard entityName != newName else { return }
           entityName = newName

           if let transform = placedTransform {
               placeModel(at: transform)
           }
       }

   private func placeModel(at worldTransform: simd_float4x4) {
       guard let aRView = aRView else { return }
       let scaleToApply = selectedEntity?.scale ?? initialScale
       // remove the old model
       if let old = placedAnchor {
           aRView.scene.removeAnchor(old)
           placedAnchor = nil
       }
       //load 3D model
       guard let modelEntity = try? ModelEntity.loadModel(named: entityName) else {
           print("failed to load model")
           return
       }
       // scale the 3D model
       modelEntity.scale = scaleToApply
       modelEntity.generateCollisionShapes(recursive: true)

       let anchorEntity = AnchorEntity(world: worldTransform)
       anchorEntity.addChild(modelEntity)
       aRView.scene.addAnchor(anchorEntity)
       aRView.installGestures([.all], for: modelEntity)

       placedAnchor = anchorEntity
       placedTransform = worldTransform
       selectedEntity = modelEntity
       print("placed/swapped model: \(entityName)")
   }

   @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
       guard let aRView = recognizer.view as? ARView else { return }
       let tapLocation = recognizer.location(in: aRView)

       let results = aRView.raycast(from: tapLocation, allowing: .estimatedPlane, alignment: .horizontal)
       guard let firstResult = results.first else {
           print("no surface found")
           return
       }

       // reuse the shared placement logic
       placeModel(at: firstResult.worldTransform)
   }
}


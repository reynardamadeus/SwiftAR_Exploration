//
//  HomeView.swift
//  ARTutorial
//
//  Created by Reynard Amadeus  on 28/07/26.
//
import SwiftUI
struct HomeView: View {
    var body: some View {
        NavigationStack{
            VStack{
                Text("Place Object on Plane by touch")
                List{
                    NavigationLink(destination: ARContainerView(entityName: "guitar", enableGesture: true).ignoresSafeArea(.all)){
                        Text("Guitar")
                    }
                    NavigationLink(destination: ARContainerView(entityName: "pancake", enableGesture: true).ignoresSafeArea(.all)){
                        Text("Pancake")
                    }
                }
                Text("Place Object on Plane automatically")
                List{
                    NavigationLink(destination: ARContainerView(entityName: "robot", enableGesture: false).ignoresSafeArea(.all)){
                        Text("Robot").foregroundStyle(Color.red)
                    }
                }
                
                Text("Swap 3D Object on Plane")
                List{
                    NavigationLink(destination: SwapModelScreenView().ignoresSafeArea(.all)){
                        Text("Truck")
                    }
                }

                Text("3D Robot Editor")
                List{
                    NavigationLink(destination: RobotEditorView().ignoresSafeArea(.all)){
                        Text("Build a Robot")
                    }
                }

            }.navigationTitle("Try AR Experience!")
            
        }
    }
}

#Preview {
    HomeView()
}

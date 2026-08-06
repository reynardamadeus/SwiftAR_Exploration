//
//  RealObstacle.swift
//  Hijauin
//
//  Created by Reynard Amadeus  on 06/08/26.
//

import Foundation

/// A detected object on the table, expressed in world space.
struct RealObstacle: Identifiable {
    let id = UUID()
    var center: SIMD3<Float>       // world-space center of the box
    var extents: SIMD3<Float>      // full width/height/depth (not half)
    var pointCount: Int            // supporting faces; a rough confidence signal
}
 
/// Describes the surface the robot drives on. Supplied by whoever detected
/// the `ARPlaneAnchor` the model was placed on.

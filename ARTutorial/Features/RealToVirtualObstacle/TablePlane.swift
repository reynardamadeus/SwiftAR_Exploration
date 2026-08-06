//
//  TablePlane.swift
//  Hijauin
//
//  Created by Reynard Amadeus  on 06/08/26.
//


struct TablePlane {
    var height: Float              // world Y of the tabletop
    var center: SIMD2<Float>       // world XZ center
    var halfExtent: SIMD2<Float>   // half width/depth of the table footprint
}
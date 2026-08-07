//
//  ZoomCamera.swift
//  Hijauin
//
//  Created by Reynard Amadeus  on 06/08/26.
//

import AVFoundation

func setZoom(_ zoom: CGFloat) {
    
    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                               for: .video,
                                               position: .back) else {
        return
    }

    do {
        try device.lockForConfiguration()

        device.videoZoomFactor = min(
            max(1.0, zoom),
            device.activeFormat.videoMaxZoomFactor
        )

        device.unlockForConfiguration()
    } catch {
        print(error)
    }
}

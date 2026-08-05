//
//  ObstacleScanner.swift
//  ARTutorial
//
//  The ONE place that knows how a physical build becomes `[DetectedObstacle]`. It
//  deliberately does the *least* computer vision that works: Vision finds coarse
//  rectangular footprints on the table, ARKit raycasts their corners onto the plane
//  to get world-space size/position, and `ObstacleKind` suggests a category the
//  child then confirms. No brick recognition.
//
//  Because everything is hidden behind `detectObstacles(in:)`, the detector can be
//  upgraded later (rectangles → VNGenerateForegroundInstanceMaskRequest → LiDAR mesh
//  sampling) without touching the coordinator, factory, or feedback code.
//
//  MVP note: if Vision returns nothing (bad lighting, tiny objects), we fall back to
//  a few demo regions in front of the camera so the rest of the loop stays playable
//  — Phases 0–4 in the roadmap need no CV at all.
//

import ARKit
import RealityKit
import Vision
import CoreGraphics

final class ObstacleScanner {

    /// Minimum footprint side (metres) we accept, to reject noise/tiny objects.
    private let minFootprint: Float = 0.03

    /// Segments the current frame into candidate obstacle regions.
    func detectObstacles(in arView: ARView) -> [DetectedObstacle] {
        guard let frame = arView.session.currentFrame else { return demoFallback() }

        let rectangles = detectRectangles(in: frame.capturedImage)
        guard !rectangles.isEmpty else { return demoFallback() }

        let viewSize = arView.bounds.size
        var results: [DetectedObstacle] = []
        for rect in rectangles {
            guard let footprint = liftToWorld(rect, arView: arView, viewSize: viewSize) else { continue }
            let side = min(footprint.size.x, footprint.size.y)
            guard side >= minFootprint else { continue }
            results.append(
                DetectedObstacle.suggested(worldCenter: footprint.center,
                                           footprint: footprint.size,
                                           yaw: 0)
            )
        }
        return results.isEmpty ? demoFallback() : results
    }

    // MARK: - Vision (coarse footprints, not bricks)

    private func detectRectangles(in pixelBuffer: CVPixelBuffer) -> [VNRectangleObservation] {
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.2
        request.maximumAspectRatio = 1.0
        request.minimumSize = 0.05          // fraction of the image
        request.maximumObservations = 6
        request.quadratureTolerance = 25

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
        do {
            try handler.perform([request])
            return request.results ?? []
        } catch {
            print("ObstacleScanner: Vision failed — \(error)")
            return []
        }
    }

    // MARK: - Lift a 2D rectangle onto the table plane

    private struct Footprint { let center: SIMD3<Float>; let size: SIMD2<Float> }

    /// Raycasts the rectangle's centre + two edge midpoints onto the horizontal
    /// plane and derives a world-space footprint. Vision coordinates are normalized
    /// with origin bottom-left, so we flip Y into view space.
    private func liftToWorld(_ rect: VNRectangleObservation, arView: ARView, viewSize: CGSize) -> Footprint? {
        func viewPoint(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * viewSize.width, y: (1 - p.y) * viewSize.height)
        }
        func worldPoint(_ p: CGPoint) -> SIMD3<Float>? {
            guard let hit = arView.raycast(from: p, allowing: .estimatedPlane, alignment: .horizontal).first
            else { return nil }
            let t = hit.worldTransform.columns.3
            return SIMD3<Float>(t.x, t.y, t.z)
        }

        let midTop = CGPoint(x: (rect.topLeft.x + rect.topRight.x) / 2,
                             y: (rect.topLeft.y + rect.topRight.y) / 2)
        let midBottom = CGPoint(x: (rect.bottomLeft.x + rect.bottomRight.x) / 2,
                                y: (rect.bottomLeft.y + rect.bottomRight.y) / 2)
        let midLeft = CGPoint(x: (rect.topLeft.x + rect.bottomLeft.x) / 2,
                              y: (rect.topLeft.y + rect.bottomLeft.y) / 2)
        let midRight = CGPoint(x: (rect.topRight.x + rect.bottomRight.x) / 2,
                               y: (rect.topRight.y + rect.bottomRight.y) / 2)

        guard
            let top = worldPoint(viewPoint(midTop)),
            let bottom = worldPoint(viewPoint(midBottom)),
            let left = worldPoint(viewPoint(midLeft)),
            let right = worldPoint(viewPoint(midRight))
        else { return nil }

        let center = (top + bottom + left + right) / 4
        let depth = simd_length(top - bottom)   // along view up → world Z-ish
        let width = simd_length(left - right)    // along view right → world X-ish
        return Footprint(center: center, size: SIMD2<Float>(width, depth))
    }

    // MARK: - Fallback (keeps the loop playable without CV)

    /// Three demo obstacles laid out ahead of the start, used when Vision finds
    /// nothing. Positions are local to the course root.
    private func demoFallback() -> [DetectedObstacle] {
        [
            DetectedObstacle(worldCenter: [0.18, 0, 0], footprint: [0.06, 0.10],
                             estimatedHeight: ObstacleKind.rock.presetHeight, kind: .rock),
            DetectedObstacle(worldCenter: [0.32, 0, 0], footprint: [0.10, 0.12],
                             estimatedHeight: ObstacleKind.ramp.presetHeight, kind: .ramp),
            DetectedObstacle(worldCenter: [0.46, 0, 0], footprint: [0.05, 0.14],
                             estimatedHeight: ObstacleKind.tunnel.presetHeight, kind: .tunnel),
        ]
    }
}

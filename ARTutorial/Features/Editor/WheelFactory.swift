//
//  WheelFactory.swift
//  ARTutorial
//
//  Builds RealityKit wheel entities. Wheels use the real bundled USDZ models
//  (wheel.usdz / gear.usdz), loaded once off the main thread via AssetCache and
//  cloned per use. Until a model has loaded, a primitive cylinder stands in.
//  `.none` returns a tappable placeholder ghost. All sizes multiply by
//  `scaleMultiplier` (driven by the kid's "Ukuran Roda" slider, range down to 0.01).
//

import RealityKit
import UIKit
import Combine

enum WheelFactory {

    // USDZ models load at an unknown native size — these base scales set the
    // default on-screen size (kept small). The slider multiplies them further.
    private static let smoothScale: Float = 0.04
    private static let offroadScale: Float = 0.06
    private static let heavyScale: Float = 0.05

    /// Base radius/height (m) for the placeholder + primitive fallback.
    private static let baseRadius: Float = 0.05
    private static let baseHeight: Float = 0.03

    /// A wheel for the type. `.none` returns a tappable placeholder.
    static func makeWheel(for type: RobotConfig.WheelType, scaleMultiplier: Float = 1) -> ModelEntity {
        switch type {
        case .none:
            return makePlaceholder(scaleMultiplier: scaleMultiplier)
        case .smooth:
            return instantiate(AssetCache.shared.wheel, scale: smoothScale * scaleMultiplier,
                               fallback: { primitiveWheel(UIColor(white: 0.8, alpha: 1), scaleMultiplier) })
        case .offroad:
            return instantiate(AssetCache.shared.wheel, scale: offroadScale * scaleMultiplier,
                               fallback: { primitiveWheel(UIColor(red: 0.38, green: 0.26, blue: 0.15, alpha: 1), scaleMultiplier) })
        case .heavy:
            return instantiate(AssetCache.shared.gear, scale: heavyScale * scaleMultiplier,
                               fallback: { primitiveWheel(UIColor(white: 0.22, alpha: 1), scaleMultiplier) })
        }
    }

    private static func instantiate(_ base: ModelEntity?, scale: Float,
                                    fallback: () -> ModelEntity) -> ModelEntity {
        if let base {
            let clone = base.clone(recursive: true)
            clone.scale = SIMD3<Float>(repeating: scale)
            clone.generateCollisionShapes(recursive: true)
            return clone
        }
        return fallback()
    }

    /// Translucent "ghost" wheel marking an empty slot. RealityKit has no
    /// dashed-line primitive, so this approximates the requested look
    /// (*garis putus-putus*) with a translucent outline. Has collision → tappable.
    static func makePlaceholder(scaleMultiplier: Float = 1) -> ModelEntity {
        let mesh = MeshResource.generateCylinder(
            height: baseHeight * scaleMultiplier,
            radius: baseRadius * scaleMultiplier
        )
        var material = UnlitMaterial(color: UIColor(white: 0.95, alpha: 1))
        material.blending = .transparent(opacity: 0.35)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        entity.name = "placeholder"
        return entity
    }

    /// Primitive cylinder used only until the matching USDZ finishes loading.
    private static func primitiveWheel(_ color: UIColor, _ scaleMultiplier: Float) -> ModelEntity {
        let mesh = MeshResource.generateCylinder(
            height: baseHeight * scaleMultiplier,
            radius: baseRadius * scaleMultiplier
        )
        let entity = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: color)])
        entity.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        return entity
    }
}

/// Loads the heavy USDZ assets once, asynchronously, and caches them for cloning.
@MainActor
final class AssetCache {

    static let shared = AssetCache()

    private(set) var wheel: ModelEntity?      // wheel.usdz
    private(set) var gear: ModelEntity?       // gear.usdz

    private var cancellables: [AnyCancellable] = []
    private var started = false
    private var completed = 0
    private var didNotify = false

    /// Fired once after all assets have settled (loaded or failed) so the scene
    /// can rebuild with the real models replacing the primitive fallbacks.
    var onLoaded: (() -> Void)?

    private init() {}

    func preload() {
        guard !started else { return }
        started = true
        load("wheel") { self.wheel = $0 }
        load("gear") { self.gear = $0 }
    }

    private func load(_ name: String, assign: @escaping (ModelEntity) -> Void) {
        let cancellable = ModelEntity.loadModelAsync(named: name)
            .sink { [weak self] completion in
                if case .failure(let error) = completion {
                    print("AssetCache: failed to load \(name) — \(error)")
                    self?.settle()
                }
            } receiveValue: { [weak self] entity in
                assign(entity)
                self?.settle()
            }
        cancellables.append(cancellable)
    }

    private func settle() {
        completed += 1
        if completed >= 2 && !didNotify {
            didNotify = true
            onLoaded?()
        }
    }
}

//
//  RobotGarage.swift
//  ARTutorial
//
//  Session-wide store of the robot currently built in the 3D editor, so other
//  screens (e.g. the bridge mission) can use the kid's car. The editor mirrors its
//  `RobotConfig` here on every change; consumers read `RobotGarage.shared.config`.
//

import Foundation
import Combine

final class RobotGarage: ObservableObject {
    static let shared = RobotGarage()

    @Published var config: RobotConfig = .default

    private init() {}
}

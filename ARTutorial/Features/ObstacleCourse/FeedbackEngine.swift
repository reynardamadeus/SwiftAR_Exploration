//
//  FeedbackEngine.swift
//  ARTutorial
//
//  Turns a resolved run into kid-friendly engineering feedback AND a concrete
//  redesign the app can pre-apply. This is the hinge of the whole learning loop:
//  every failure names a cause a 6–10 year old understands and hands back a mutated
//  `RobotConfig` so "Fix it for me" drops them into the editor with the suggested
//  change already made — feedback (#7) → redesign (#8) → retest (#9).
//
//  Pure rules, no ML. Deterministic and easy to tune with teachers.
//

import Foundation

/// A single piece of advice plus the edit it implies.
struct EngineeringFeedback: Identifiable {
    let id = UUID()
    let isSuccess: Bool
    /// One-sentence, kid-facing message (Indonesian to match the app UI).
    let childMessage: String
    /// Plain-language engineering reason (for a teacher/parent or an info tap).
    let engineeringReason: String
    /// Applies the suggested design change; identity for success.
    let suggestedConfigChange: (RobotConfig) -> RobotConfig
}

enum FeedbackEngine {

    /// Maps outcome + telemetry + current design → feedback.
    static func feedback(for run: CourseRunComponent, config: RobotConfig) -> EngineeringFeedback {
        switch run.outcome {

        case .success:
            let tire = VehicleFactory.dominantTire(config)
            return EngineeringFeedback(
                isSuccess: true,
                childMessage: "Hebat! Mobilmu sampai garis finish! 🎉",
                engineeringReason: "The \(tire.displayName) tires and the current"
                    + " clearance/height carried the vehicle through the course.",
                suggestedConfigChange: { $0 } // nothing to change
            )

        case .stuck:
            // Stalled without a body hit → grip problem. Push toward grippier tires.
            return EngineeringFeedback(
                isSuccess: false,
                childMessage: "Rodanya selip! Coba pakai Roda Pegunungan yang lebih menggigit.",
                engineeringReason: "The vehicle stalled with no chassis contact — low"
                    + " tire friction couldn't generate traction on the slope/surface.",
                suggestedConfigChange: { setAllTires($0, to: .offroad) }
            )

        case .chassisCollision:
            return EngineeringFeedback(
                isSuccess: false,
                childMessage: "Bagian bawah mobil kena batu. Pakai roda lebih besar biar tinggi!",
                engineeringReason: "The chassis contacted an obstacle: insufficient ground"
                    + " clearance. Larger wheels raise the body over low obstacles.",
                suggestedConfigChange: { increaseWheelScale($0) }
            )

        case .tooTallForTunnel:
            return EngineeringFeedback(
                isSuccess: false,
                childMessage: "Mobilmu terlalu tinggi untuk terowongan. Buat lebih pendek!",
                engineeringReason: "The body silhouette exceeded the opening height."
                    + " Reducing body height lets it pass under.",
                suggestedConfigChange: { lowerBody($0) }
            )

        case .flipped:
            return EngineeringFeedback(
                isSuccess: false,
                childMessage: "Mobilmu terbalik! Buat lebih lebar dan pendek biar stabil.",
                engineeringReason: "Tilt exceeded the recovery angle: the center of"
                    + " gravity is too high/narrow. A wider, lower body is more stable.",
                suggestedConfigChange: { widenAndLower($0) }
            )

        case .timeout:
            return EngineeringFeedback(
                isSuccess: false,
                childMessage: "Belum sampai. Coba roda lebih besar biar lebih kuat!",
                engineeringReason: "Ran out of time with no clear blocker — likely too"
                    + " little clearance/traction to keep momentum.",
                suggestedConfigChange: { increaseWheelScale($0) }
            )

        case .running:
            return EngineeringFeedback(
                isSuccess: false,
                childMessage: "Masih berjalan…",
                engineeringReason: "Run not yet resolved.",
                suggestedConfigChange: { $0 }
            )
        }
    }

    // MARK: - Config mutations (each returns a new config)

    private static func setAllTires(_ c: RobotConfig, to type: RobotConfig.WheelType) -> RobotConfig {
        var out = c
        for slot in WheelSlot.allCases where out[slot].type != .none {
            out[slot].type = type
        }
        return out
    }

    private static func increaseWheelScale(_ c: RobotConfig) -> RobotConfig {
        var out = c
        out.wheelScale = min(out.wheelScale * 1.4, 0.4)
        return out
    }

    private static func lowerBody(_ c: RobotConfig) -> RobotConfig {
        var out = c
        out.bodySize.height = max(out.bodySize.height * 0.7, 0.2)
        return out
    }

    private static func widenAndLower(_ c: RobotConfig) -> RobotConfig {
        var out = c
        out.bodySize.width = out.bodySize.width * 1.3
        out.bodySize.height = max(out.bodySize.height * 0.8, 0.2)
        return out
    }
}

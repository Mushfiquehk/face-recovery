import Foundation
import SwiftData

/// The LLM's assessment of the photograph itself rather than the face in it. Rated on every
/// Face Scan; gates whether the scan feeds the Personal Baseline and trends.
@Model
final class CaptureQuality {
    /// 0-100, higher = better lit.
    var lighting: Int
    /// 0-100, higher = sharper.
    var sharpness: Int
    var faceFullyVisible: Bool
    /// The model's own verdict on whether the photo can be rated at all.
    var isUsable: Bool

    var scan: FaceScan?

    init(lighting: Int, sharpness: Int, faceFullyVisible: Bool, isUsable: Bool) {
        self.lighting = lighting
        self.sharpness = sharpness
        self.faceFullyVisible = faceFullyVisible
        self.isUsable = isUsable
    }

    /// Why a scan was ruled unusable, for the day detail screen. Empty when usable.
    var failureReasons: [String] {
        guard !isUsable else { return [] }
        var reasons: [String] = []
        if !faceFullyVisible { reasons.append("Face not fully visible") }
        if lighting < 40 { reasons.append("Lighting too poor") }
        if sharpness < 40 { reasons.append("Photo too soft") }
        if reasons.isEmpty { reasons.append("Rated unusable by the model") }
        return reasons
    }
}

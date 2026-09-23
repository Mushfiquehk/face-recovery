import Foundation
import SwiftData

/// The five directly observable facial characteristics the LLM rates for a Face Scan.
/// `holisticTiredness` is rated and baselined alongside them but is not a Signal and is
/// deliberately excluded from the Recovery Score (CONTEXT.md, ADR 0002).
enum Signal: String, CaseIterable, Identifiable, Codable {
    case underEyeDarkness
    case underEyePuffiness
    case facialPuffiness
    case eyeRedness
    case skinDullness

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .underEyeDarkness: "Under-eye darkness"
        case .underEyePuffiness: "Under-eye puffiness"
        case .facialPuffiness: "Facial puffiness"
        case .eyeRedness: "Eye redness"
        case .skinDullness: "Skin dullness"
        }
    }

    /// The key this Signal uses in the scoring JSON schema and in exports.
    var jsonKey: String {
        switch self {
        case .underEyeDarkness: "under_eye_darkness"
        case .underEyePuffiness: "under_eye_puffiness"
        case .facialPuffiness: "facial_puffiness"
        case .eyeRedness: "eye_redness"
        case .skinDullness: "skin_dullness"
        }
    }
}

/// Absolute Signals: what the LLM rated from one photo alone, with no reference image and no
/// history in the prompt. Never mutated after the Scoring Run that produced them (ADR 0002).
@Model
final class SignalSet {
    /// 0-100 for every rating. Higher always means the fatigue marker is more pronounced.
    var underEyeDarkness: Int
    var underEyePuffiness: Int
    var facialPuffiness: Int
    var eyeRedness: Int
    var skinDullness: Int

    /// The LLM's overall impression of how tired the face looks. Stored and baselined,
    /// never part of the Recovery Score.
    var holisticTiredness: Int

    var scan: FaceScan?

    init(
        underEyeDarkness: Int,
        underEyePuffiness: Int,
        facialPuffiness: Int,
        eyeRedness: Int,
        skinDullness: Int,
        holisticTiredness: Int
    ) {
        self.underEyeDarkness = underEyeDarkness
        self.underEyePuffiness = underEyePuffiness
        self.facialPuffiness = facialPuffiness
        self.eyeRedness = eyeRedness
        self.skinDullness = skinDullness
        self.holisticTiredness = holisticTiredness
    }

    subscript(signal: Signal) -> Int {
        switch signal {
        case .underEyeDarkness: underEyeDarkness
        case .underEyePuffiness: underEyePuffiness
        case .facialPuffiness: facialPuffiness
        case .eyeRedness: eyeRedness
        case .skinDullness: skinDullness
        }
    }

    /// The five observable Signals, in canonical order. Holistic Tiredness is not included.
    var observed: [Int] { Signal.allCases.map { self[$0] } }
}

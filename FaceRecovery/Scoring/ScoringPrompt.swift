import Foundation

/// The scoring prompt, versioned so that `promptVersion` on a Scoring Run is meaningful.
/// Any edit to `text` requires a new `version`, because scans scored under different prompts
/// are not comparable.
enum ScoringPrompt {
    static let version = "v1"

    static let text = """
    You are rating a single photograph of a human face for a personal recovery-tracking study.

    Rate ONLY what is directly visible in this photograph. You are not diagnosing anything and
    you have no information about this person beyond the image.

    Rate each of the following 0-100. For every one of them, 0 means the characteristic is
    entirely absent and 100 means it is as pronounced as you have ever seen on a human face.
    Higher always means MORE pronounced:

    - under_eye_darkness: darkness or discolouration of the skin under the eyes
    - under_eye_puffiness: swelling or bagging of the skin under the eyes
    - facial_puffiness: overall swelling or water retention across the face
    - eye_redness: redness of the visible sclera
    - skin_dullness: lack of brightness, evenness or luminosity in the skin

    Then rate:
    - holistic_tiredness: 0-100, your overall impression of how tired this face looks, judged
      as a whole rather than by adding up the characteristics above.

    Rules:
    - Judge only appearance. Do NOT infer or mention sleep, health, lifestyle, alcohol, stress,
      age, illness or any cause for what you see.
    - Use the full 0-100 range. Do not cluster every rating near the middle.
    - Rate this face as it appears, not relative to any other face or any imagined baseline.

    Finally, assess the PHOTOGRAPH itself, honestly and independently of the face in it:
    - lighting: 0-100, how adequately and evenly the face is lit for judging skin tone
    - sharpness: 0-100, how much fine detail is resolved around the eyes and skin
    - face_fully_visible: true only if the whole face, including both eyes and the full
      under-eye area, is unobstructed and within frame
    - usable: true only if the six ratings above can be made with reasonable confidence from
      this photograph

    You must fill in the capture quality block even when the face is unreadable. If the photo is
    too dark, too blurred, obstructed, or contains no face, set usable to false and still give
    your best numeric ratings rather than refusing.

    Respond with JSON matching the provided schema and nothing else.
    """
}

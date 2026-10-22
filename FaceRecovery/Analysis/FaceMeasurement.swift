import CoreGraphics
import Foundation
import ImageIO
import Vision

/// The Absolute Signals and Capture Quality of one Face Scan, measured on the device from Apple
/// Vision landmarks and pixel arithmetic (ADR 0005). This file is also compiled into the research
/// pipeline's command-line tool, so the research and the app can never measure differently.
struct FaceMeasurement: Codable, Equatable {
    /// Bump whenever any number below would come out differently for the same photo. Every stored
    /// scan is then re-measured; versions are never mixed.
    static let currentVersion = "m1"

    var version: String
    /// Signal id → value. Units and meaning per id are in `SignalCatalog`.
    var signals: [String: Double]
    var quality: Quality
    /// Where each Signal was read, as polygons in the upright photo: x and y in 0-1, origin top-left.
    /// Lets the app outline the area behind each Contribution.
    var regions: [String: [[Double]]]

    struct Quality: Codable, Equatable {
        var faceAreaFraction: Double
        var yawDegrees: Double
        var rollDegrees: Double
        var pitchDegrees: Double
        /// Median cheek lightness, CIELAB L* (0 black - 100 white).
        var brightness: Double
        /// Variance of the Laplacian around the eyes, after scaling every face to the same size.
        var sharpness: Double
        /// Share of eye pixels blown out to white: glare, usually from glasses.
        var eyeGlare: Double
        /// Apple's own 0-1 judgement of how suitable the face capture is.
        var visionCaptureQuality: Double
        /// How strongly one horizontal line (a spectacle rim) stands out below the eyes; about 1-2
        /// for bare skin, higher with glasses on.
        var glassesScore: Double
        /// Hue of the cheek in CIELAB degrees. Skin sits in a narrow band under white light, so a
        /// value outside it means coloured light, which would be read as a change in the face.
        var skinHueDegrees: Double
        var usable: Bool
        /// Plain-language reasons the scan is unusable; empty when usable.
        var problems: [String]
    }
}

enum FaceMeasurementError: Error, Equatable {
    case unreadableImage
    case noFace
}

enum FaceMeasurer {
    // Every face is redrawn upright on a fixed canvas with the eyes level and this far apart, so
    // regions, sharpness and geometry mean the same thing whatever the photo's size or head tilt.
    static let interocular = 120.0
    static let canvasWidth = 400
    static let canvasHeight = 520
    static let eyeLineY = 200.0  // from the top of the canvas

    // Capture Quality thresholds.
    static let maxAngleDegrees = 20.0
    static let minFaceAreaFraction = 0.04
    static let brightnessRange = 25.0...92.0
    static let minSharpness = 12.0
    static let maxEyeGlare = 0.06
    // Glasses are always off for a scan: lenses shrink the eyes, tint the skin under them and
    // their rims cross the cheek patch. On the developer's photos bare faces scored 1.6-3.0 and
    // faces with glasses 6.2-13.
    static let maxGlassesScore = 4.5
    static let skinHueRange = 35.0...75.0

    /// Decodes image data upright (EXIF orientation applied) and measures it.
    static func measure(imageData: Data) throws -> FaceMeasurement {
        guard let image = uprightImage(from: imageData) else { throw FaceMeasurementError.unreadableImage }
        return try measure(image)
    }

    static func uprightImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func measure(_ image: CGImage) throws -> FaceMeasurement {
        // Head pose comes from the rectangles request; landmarks and capture quality refine that face.
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        let rectanglesRequest = VNDetectFaceRectanglesRequest()
        rectanglesRequest.revision = VNDetectFaceRectanglesRequestRevision3
        runOnCPUInSimulator(rectanglesRequest)
        try handler.perform([rectanglesRequest])
        guard let found = rectanglesRequest.results?.max(by: { area($0.boundingBox) < area($1.boundingBox) }) else {
            throw FaceMeasurementError.noFace
        }
        let landmarksRequest = VNDetectFaceLandmarksRequest()
        landmarksRequest.revision = VNDetectFaceLandmarksRequestRevision3
        landmarksRequest.constellation = .constellation76Points
        landmarksRequest.inputFaceObservations = [found]
        runOnCPUInSimulator(landmarksRequest)
        let qualityRequest = VNDetectFaceCaptureQualityRequest()
        qualityRequest.inputFaceObservations = [found]
        runOnCPUInSimulator(qualityRequest)
        try handler.perform([landmarksRequest, qualityRequest])
        let captureQuality = Double(qualityRequest.results?.first?.faceCaptureQuality ?? 0)

        guard let face = landmarksRequest.results?.first,
              let marks = face.landmarks,
              let leftEyeRegion = marks.leftEye, let rightEyeRegion = marks.rightEye,
              let outerLips = marks.outerLips, let contour = marks.faceContour else {
            throw FaceMeasurementError.noFace
        }

        let size = CGSize(width: image.width, height: image.height)
        func points(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
            region?.pointsInImage(imageSize: size) ?? []  // pixels, origin bottom-left
        }

        // Image-left and image-right, whatever Vision calls them.
        let eyePair = [points(leftEyeRegion), points(rightEyeRegion)].sorted { mean($0).x < mean($1).x }
        let browPair = [points(marks.leftEyebrow), points(marks.rightEyebrow)].sorted { mean($0).x < mean($1).x }
        let pupilPair = [points(marks.leftPupil), points(marks.rightPupil)].filter { !$0.isEmpty }
            .sorted { mean($0).x < mean($1).x }
        let centres = eyePair.map(mean)
        let dx = centres[1].x - centres[0].x, dy = centres[1].y - centres[0].y
        let distance = hypot(dx, dy)
        guard distance > 0 else { throw FaceMeasurementError.noFace }

        let toCanvas = CGAffineTransform(translationX: -(centres[0].x + centres[1].x) / 2,
                                         y: -(centres[0].y + centres[1].y) / 2)
            .concatenating(CGAffineTransform(rotationAngle: -atan2(dy, dx)))
            .concatenating(CGAffineTransform(scaleX: interocular / distance, y: interocular / distance))
            .concatenating(CGAffineTransform(translationX: Double(canvasWidth) / 2,
                                             y: Double(canvasHeight) - eyeLineY))
        guard let canvas = Canvas(image: image, transform: toCanvas) else {
            throw FaceMeasurementError.unreadableImage
        }
        // Canvas coordinates from here on: pixels, origin top-left, eyes level on y = eyeLineY.
        func onCanvas(_ pts: [CGPoint]) -> [CGPoint] {
            pts.map { p in
                let q = p.applying(toCanvas)
                return CGPoint(x: q.x, y: Double(canvasHeight) - q.y)
            }
        }
        let eyes = eyePair.map(onCanvas)
        let brows = browPair.map(onCanvas)
        let pupils = pupilPair.count == 2 ? pupilPair.map { mean(onCanvas($0)) } : eyes.map(mean)
        let lips = onCanvas(points(outerLips))
        let jaw = onCanvas(points(contour))

        var regions: [String: [CGPoint]] = [:]
        var under: [Pixel] = [], cheek: [Pixel] = [], sclera: [Pixel] = [], eyePixels: [Pixel] = []
        var apertures: [Double] = [], heights: [Double] = [], browGaps: [Double] = [], rims: [Double] = []
        var openings: [Double] = []

        for (side, eye) in eyes.enumerated() {
            let xs = eye.map(\.x), ys = eye.map(\.y)
            let width = xs.max()! - xs.min()!
            guard width > 0 else { throw FaceMeasurementError.noFace }
            let centreX = (xs.max()! + xs.min()!) / 2
            let bottom = ys.max()!, top = ys.min()!
            apertures.append(polygonArea(eye) / (width * width))
            heights.append((bottom - top) / width)
            if let opening = canvas.lidGap(pupil: pupils[side], eyeWidth: width) {
                openings.append(opening / width)
            }
            if brows[side].count > 0 {
                browGaps.append((top - mean(brows[side]).y) / interocular)
            }

            // Under-eye band just below the lower lid; cheek further down in the same column.
            let underBox = CGRect(x: centreX - width / 2, y: bottom + 0.08 * width, width: width, height: 0.37 * width)
            let cheekBox = CGRect(x: centreX - width / 2, y: bottom + 0.65 * width, width: width, height: 0.35 * width)
            rims.append(canvas.strongestHorizontalLine(in: CGRect(
                x: centreX - 0.7 * width, y: bottom + 0.2 * width, width: 1.4 * width, height: 1.2 * width)))
            under += canvas.pixels(in: underBox)
            cheek += canvas.pixels(in: cheekBox)
            let inside = canvas.pixels(inPolygon: eye)
            eyePixels += inside
            // The sclera is the brightest part of the eye; blown-out glare is not sclera.
            let unclipped = inside.filter { !$0.isClipped }
            let cut = percentile(unclipped.map(\.luminance), 0.65)
            sclera += unclipped.filter { $0.luminance >= cut }

            let tag = side == 0 ? "left" : "right"
            regions["eye_\(tag)"] = eye
            regions["under_eye_\(tag)"] = corners(underBox)
            regions["cheek_\(tag)"] = corners(cheekBox)
        }
        regions["mouth"] = lips
        guard !under.isEmpty, !cheek.isEmpty, !sclera.isEmpty else { throw FaceMeasurementError.noFace }

        let underLab = medianLab(under), cheekLab = medianLab(cheek), scleraLab = medianLab(sclera)
        let underLinear = medianLinear(under), cheekLinear = medianLinear(cheek), scleraLinear = medianLinear(sclera)

        // Mouth corners relative to the middle of the lips; positive means the corners sit lower.
        let mouthCorners = [lips.min { $0.x < $1.x }!, lips.max { $0.x < $1.x }!]
        let lipCentreY = mean(lips).y
        let jawXs = jaw.map(\.x)

        var signals: [String: Double] = [
            "eye_aperture": mean(apertures),
            "eye_height": mean(heights),
            "eye_opening_edges": mean(openings),
            "under_eye_shadow": cheekLab.l - underLab.l,
            "under_eye_contrast": 1 - underLinear.luminance / max(cheekLinear.luminance, 1e-6),
            "under_eye_blue": log((underLinear.b / underLinear.g) / (cheekLinear.b / cheekLinear.g)),
            "sclera_redness": scleraLab.a,
            "sclera_vs_skin_redness": log((scleraLinear.r / scleraLinear.g) / (cheekLinear.r / cheekLinear.g)),
            "skin_chroma": hypot(cheekLab.a, cheekLab.b),
            "mouth_corner_droop": (mean(mouthCorners.map { Double($0.y) }) - lipCentreY) / interocular,
            "face_width": ((jawXs.max() ?? 0) - (jawXs.min() ?? 0)) / interocular,
        ]
        if !browGaps.isEmpty { signals["brow_gap"] = mean(browGaps) }
        signals = signals.filter { $0.value.isFinite }

        let glare = Double(eyePixels.filter(\.isClipped).count) / Double(max(eyePixels.count, 1))
        let eyeArea = CGRect(x: Double(canvasWidth) / 2 - 1.4 * interocular / 2 - 30, y: eyeLineY - 40,
                             width: 1.4 * interocular + 60, height: 90)
        var quality = FaceMeasurement.Quality(
            faceAreaFraction: area(face.boundingBox),
            yawDegrees: degrees(found.yaw), rollDegrees: degrees(found.roll), pitchDegrees: degrees(found.pitch),
            brightness: cheekLab.l,
            sharpness: canvas.laplacianVariance(in: eyeArea),
            eyeGlare: glare,
            visionCaptureQuality: captureQuality,
            glassesScore: mean(rims),
            skinHueDegrees: atan2(cheekLab.b, cheekLab.a) * 180 / .pi,
            usable: true, problems: []
        )
        quality.problems = problems(quality)
        quality.usable = quality.problems.isEmpty

        let back = toCanvas.inverted()
        func normalised(_ pts: [CGPoint]) -> [[Double]] {
            pts.map { p in
                let q = CGPoint(x: p.x, y: Double(canvasHeight) - p.y).applying(back)
                return [q.x / size.width, 1 - q.y / size.height]
            }
        }
        return FaceMeasurement(version: FaceMeasurement.currentVersion, signals: signals, quality: quality,
                               regions: regions.mapValues(normalised))
    }

    /// Why a scan is unusable, in words a user can act on. Empty means usable.
    static func problems(_ q: FaceMeasurement.Quality) -> [String] {
        var out: [String] = []
        if abs(q.yawDegrees) > maxAngleDegrees || abs(q.pitchDegrees) > maxAngleDegrees {
            out.append("Face the camera straight on.")
        }
        if abs(q.rollDegrees) > maxAngleDegrees { out.append("Hold your head level.") }
        if q.faceAreaFraction < minFaceAreaFraction { out.append("Hold the phone closer to your face.") }
        if q.brightness < brightnessRange.lowerBound { out.append("It is too dark. Face a window or a lamp.") }
        if q.brightness > brightnessRange.upperBound { out.append("It is too bright. Move out of direct light.") }
        if q.sharpness < minSharpness { out.append("The photo is blurry. Hold the phone still.") }
        if q.glassesScore > maxGlassesScore { out.append("Take off your glasses for the scan.") }
        if q.eyeGlare > maxEyeGlare { out.append("There is a bright reflection on your eyes.") }
        if !skinHueRange.contains(q.skinHueDegrees) {
            out.append("The light is strongly coloured. Use daylight or a white lamp.")
        }
        return out
    }

    // MARK: - Helpers

    /// The iOS Simulator cannot create Vision's GPU or Neural Engine context ("Could not create
    /// inference context"), so there the requests run on the CPU. Devices and the Mac tool are
    /// left on Vision's own choice.
    private static func runOnCPUInSimulator(_ request: VNRequest) {
        #if targetEnvironment(simulator)
        guard let stages = try? request.supportedComputeStageDevices else { return }
        for (stage, devices) in stages {
            if let cpu = devices.first(where: { if case .cpu = $0 { true } else { false } }) {
                request.setComputeDevice(cpu, for: stage)
            }
        }
        #endif
    }

    private static func area(_ r: CGRect) -> Double { r.width * r.height }
    private static func degrees(_ radians: NSNumber?) -> Double { (radians?.doubleValue ?? 0) * 180 / .pi }

    private static func mean(_ pts: [CGPoint]) -> CGPoint {
        let n = Double(max(pts.count, 1))
        return CGPoint(x: pts.reduce(0) { $0 + $1.x } / n, y: pts.reduce(0) { $0 + $1.y } / n)
    }

    private static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? .nan : values.reduce(0, +) / Double(values.count)
    }

    private static func polygonArea(_ pts: [CGPoint]) -> Double {
        guard pts.count >= 3 else { return 0 }
        var sum = 0.0
        for i in pts.indices {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    private static func corners(_ r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
         CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
    }

    private static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return .infinity }
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(p * Double(sorted.count)))]
    }

    private static func median(_ values: [Double]) -> Double { percentile(values, 0.5) }

    private static func medianLinear(_ px: [Pixel]) -> (r: Double, g: Double, b: Double, luminance: Double) {
        (median(px.map(\.r)), median(px.map(\.g)), median(px.map(\.b)), median(px.map(\.luminance)))
    }

    private static func medianLab(_ px: [Pixel]) -> (l: Double, a: Double, b: Double) {
        let labs = px.map(\.lab)
        return (median(labs.map(\.0)), median(labs.map(\.1)), median(labs.map(\.2)))
    }
}

/// One pixel in linear-light RGB (0-1), with whether any channel was clipped at full scale.
struct Pixel {
    let r: Double, g: Double, b: Double
    let isClipped: Bool

    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    /// CIELAB, D65 white.
    var lab: (Double, Double, Double) {
        let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
        let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116.0 }
        return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
    }
}

/// The face redrawn upright, level and at a fixed scale, as 8-bit sRGB.
private struct Canvas {
    let width = FaceMeasurer.canvasWidth
    let height = FaceMeasurer.canvasHeight
    private var bytes: [UInt8]

    private static let toLinear: [Double] = (0..<256).map { i in
        let c = Double(i) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    init?(image: CGImage, transform: CGAffineTransform) {
        bytes = [UInt8](repeating: 0, count: FaceMeasurer.canvasWidth * FaceMeasurer.canvasHeight * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: buffer.baseAddress, width: FaceMeasurer.canvasWidth,
                                          height: FaceMeasurer.canvasHeight, bitsPerComponent: 8,
                                          bytesPerRow: FaceMeasurer.canvasWidth * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .high
            context.concatenate(transform)
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        if !drawn { return nil }
    }

    /// Row 0 of the bitmap is the top of the canvas.
    func pixel(_ x: Int, _ y: Int) -> Pixel? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let i = (y * width + x) * 4
        guard bytes[i + 3] > 0 else { return nil }  // outside the photo
        let r = bytes[i], g = bytes[i + 1], b = bytes[i + 2]
        return Pixel(r: Self.toLinear[Int(r)], g: Self.toLinear[Int(g)], b: Self.toLinear[Int(b)],
                     isClipped: max(r, g, b) >= 250)
    }

    func pixels(in rect: CGRect) -> [Pixel] {
        var out: [Pixel] = []
        for y in Int(rect.minY.rounded())..<Int(rect.maxY.rounded()) {
            for x in Int(rect.minX.rounded())..<Int(rect.maxX.rounded()) {
                if let p = pixel(x, y) { out.append(p) }
            }
        }
        return out
    }

    func pixels(inPolygon poly: [CGPoint]) -> [Pixel] {
        guard poly.count >= 3 else { return [] }
        let xs = poly.map(\.x), ys = poly.map(\.y)
        var out: [Pixel] = []
        for y in Int(ys.min()!.rounded(.down))...Int(ys.max()!.rounded(.up)) {
            for x in Int(xs.min()!.rounded(.down))...Int(xs.max()!.rounded(.up))
            where contains(poly, CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)) {
                if let p = pixel(x, y) { out.append(p) }
            }
        }
        return out
    }

    func laplacianVariance(in rect: CGRect) -> Double {
        func grey(_ x: Int, _ y: Int) -> Double? {
            guard let p = pixel(x, y) else { return nil }
            return 255 * pow(p.luminance, 1 / 2.2)
        }
        var values: [Double] = []
        for y in Int(rect.minY) + 1..<Int(rect.maxY) - 1 {
            for x in Int(rect.minX) + 1..<Int(rect.maxX) - 1 {
                guard let c = grey(x, y), let u = grey(x, y - 1), let d = grey(x, y + 1),
                      let l = grey(x - 1, y), let r = grey(x + 1, y) else { continue }
                values.append(u + d + l + r - 4 * c)
            }
        }
        guard values.count > 1 else { return 0 }
        let m = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(values.count - 1)
    }

    /// Distance between the upper and lower eyelid edges, found in the pixels of a narrow strip
    /// through the pupil rather than taken from Vision's coarse eye outline: the upper lid is the
    /// sharpest bright-to-dark step above the pupil, the lower lid the sharpest dark-to-bright
    /// step below it.
    func lidGap(pupil: CGPoint, eyeWidth w: Double) -> Double? {
        let x0 = Int((pupil.x - 0.12 * w).rounded()), x1 = Int((pupil.x + 0.12 * w).rounded())
        let y0 = Int((pupil.y - 0.7 * w).rounded()), y1 = Int((pupil.y + 0.7 * w).rounded())
        guard x1 > x0, y1 - y0 > 8 else { return nil }
        var profile: [Int: Double] = [:]
        for y in y0...y1 {
            var sum = 0.0, n = 0
            for x in x0...x1 {
                if let p = pixel(x, y) { sum += pow(p.luminance, 1 / 2.2); n += 1 }
            }
            if n > 0 { profile[y] = sum / Double(n) }
        }
        func step(_ y: Int) -> Double? {
            guard let above = profile[y - 2], let below = profile[y + 2] else { return nil }
            return below - above
        }
        let centre = Int(pupil.y.rounded()), margin = max(2, Int(0.05 * w))
        let upper = (y0 + 2...centre - margin).compactMap { y in step(y).map { (y, -$0) } }.max { $0.1 < $1.1 }
        let lower = (centre + margin...y1 - 2).compactMap { y in step(y).map { (y, $0) } }.max { $0.1 < $1.1 }
        guard let upper, let lower, upper.1 > 0, lower.1 > 0 else { return nil }
        return Double(lower.0 - upper.0)
    }

    /// Peak row-mean of vertical brightness change in `rect`, divided by the median row: a frame
    /// rim is one sharp line across the whole width, skin texture is not.
    func strongestHorizontalLine(in rect: CGRect) -> Double {
        var rows: [Double] = []
        for y in Int(rect.minY) + 1..<Int(rect.maxY) - 1 {
            var sum = 0.0, n = 0
            for x in Int(rect.minX)..<Int(rect.maxX) {
                guard let up = pixel(x, y - 1), let down = pixel(x, y + 1) else { continue }
                sum += abs(pow(down.luminance, 1 / 2.2) - pow(up.luminance, 1 / 2.2))
                n += 1
            }
            if n > 0 { rows.append(sum / Double(n)) }
        }
        guard rows.count > 2 else { return 0 }
        let sorted = rows.sorted()
        return sorted.last! / max(sorted[sorted.count / 2], 1e-6)
    }

    private func contains(_ poly: [CGPoint], _ p: CGPoint) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in poly.indices {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}

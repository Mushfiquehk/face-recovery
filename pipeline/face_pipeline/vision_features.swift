// Apple Vision face measurements for the research strand: runs on this Mac, so photos never leave it.
//
// Usage: swift vision_features.swift IMAGE...
// Prints one JSON object per image (JSON Lines) with:
//   face      - largest face bounding box, normalized, origin top-left
//   landmarks - Vision's landmark regions as [[x, y], ...] in normalized image coordinates (top-left)
//   embedding - Vision feature print of the face crop (generic image embedding, not identity)
// or {"path": ..., "error": ...} when no face is found.

import CoreImage
import Foundation
import ImageIO
import Vision

func loadUpright(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
    let orientation = (props[kCGImagePropertyOrientation] as? UInt32) ?? 1
    let ci = CIImage(contentsOf: url)?.oriented(forExifOrientation: Int32(orientation))
    guard let ci else { return nil }
    return CIContext().createCGImage(ci, from: ci.extent)
}

func points(_ region: VNFaceLandmarkRegion2D?, in box: CGRect) -> [[Double]] {
    guard let region else { return [] }
    return region.normalizedPoints.map { p in
        // Region points are relative to the face box, origin bottom-left; flip to top-left.
        let x = box.minX + Double(p.x) * box.width
        let y = box.minY + Double(p.y) * box.height
        return [x, 1 - y]
    }
}

func emit(_ object: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: object)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
}

for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    guard let image = loadUpright(url) else {
        emit(["path": path, "error": "unreadable image"])
        continue
    }
    let handler = VNImageRequestHandler(cgImage: image)
    let landmarksRequest = VNDetectFaceLandmarksRequest()
    do { try handler.perform([landmarksRequest]) } catch {
        emit(["path": path, "error": "\(error)"])
        continue
    }
    guard let face = landmarksRequest.results?.max(by: {
        $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
    }), let marks = face.landmarks else {
        emit(["path": path, "error": "no face found"])
        continue
    }
    let box = face.boundingBox

    // Feature print of the face crop only, so background and clothing do not dominate it.
    let width = Double(image.width), height = Double(image.height)
    let crop = CGRect(x: box.minX * width, y: (1 - box.maxY) * height,
                      width: box.width * width, height: box.height * height).integral
    var embedding: [Float] = []
    if let faceImage = image.cropping(to: crop) {
        let printRequest = VNGenerateImageFeaturePrintRequest()
        try? VNImageRequestHandler(cgImage: faceImage).perform([printRequest])
        if let observation = printRequest.results?.first as? VNFeaturePrintObservation {
            embedding = observation.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        }
    }

    emit([
        "path": path,
        "width": image.width,
        "height": image.height,
        "face": [box.minX, 1 - box.maxY, box.width, box.height],
        "landmarks": [
            "left_eye": points(marks.leftEye, in: box),
            "right_eye": points(marks.rightEye, in: box),
            "left_eyebrow": points(marks.leftEyebrow, in: box),
            "right_eyebrow": points(marks.rightEyebrow, in: box),
            "nose": points(marks.nose, in: box),
            "outer_lips": points(marks.outerLips, in: box),
            "face_contour": points(marks.faceContour, in: box),
        ],
        "embedding": embedding,
    ])
}

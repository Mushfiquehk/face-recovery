// face-measure: runs the app's own FaceMeasurement on this Mac for the research pipeline.
//
// Built from FaceRecovery/Analysis/FaceMeasurement.swift plus this file (see research.py), so it
// measures exactly as the phone does. Usage: face-measure IMAGE...
// Prints one JSON object per image: {"path", "measurement"} or {"path", "error"}.

import Foundation

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]

for path in CommandLine.arguments.dropFirst() {
    var line: [String: Any] = ["path": path]
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let measurement = try FaceMeasurer.measure(imageData: data)
        line["measurement"] = try JSONSerialization.jsonObject(with: encoder.encode(measurement))
    } catch {
        line["error"] = "\(error)"
    }
    FileHandle.standardOutput.write(try! JSONSerialization.data(withJSONObject: line))
    FileHandle.standardOutput.write(Data("\n".utf8))
}

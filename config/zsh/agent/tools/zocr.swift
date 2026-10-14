// zocr <image-path> — Apple Vision text recognition, one JSON object per line + a summary.
// Compiled lazily by agent.py (swiftc -O), not at shell startup. No dependencies beyond
// what macOS ships. Exit 2 on any failure to load/process the image (agent.py treats that
// as "no OCR available" and falls straight to sending the image itself).
import AppKit
import Foundation
import Vision

func jsonLine(_ d: [String: Any]) -> String {
    if let data = try? JSONSerialization.data(withJSONObject: d),
       let s = String(data: data, encoding: .utf8) { return s }
    return "{}"
}

guard CommandLine.arguments.count > 1,
      let img = NSImage(contentsOfFile: CommandLine.arguments[1]),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    FileHandle.standardError.write("zocr: could not load image\n".data(using: .utf8)!)
    exit(2)
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = true
if #available(macOS 13.0, *) { request.automaticallyDetectsLanguage = true }

let handler = VNImageRequestHandler(cgImage: cg, options: [:])
do {
    try handler.perform([request])
} catch {
    FileHandle.standardError.write("zocr: recognition failed: \(error)\n".data(using: .utf8)!)
    exit(2)
}

let results = (request.results ?? []) as [VNRecognizedTextObservation]
// top-to-bottom, then left-to-right: boundingBox is normalized (0,0)=bottom-left,
// so higher maxY = higher on screen, and for near-equal rows sort by minX.
let sorted = results.sorted { a, b in
    if abs(a.boundingBox.maxY - b.boundingBox.maxY) > 0.01 {
        return a.boundingBox.maxY > b.boundingBox.maxY
    }
    return a.boundingBox.minX < b.boundingBox.minX
}

var totalArea = 0.0
var totalChars = 0
var confSum = 0.0
var confN = 0

for obs in sorted {
    guard let candidate = obs.topCandidates(1).first else { continue }
    let b = obs.boundingBox
    totalArea += Double(b.width) * Double(b.height)
    totalChars += candidate.string.count
    confSum += Double(candidate.confidence)
    confN += 1
    print(jsonLine([
        "t": candidate.string,
        "c": Double(candidate.confidence),
        "x": Double(b.minX), "y": Double(1 - b.maxY),   // flip to top-left origin for callers
        "w": Double(b.width), "h": Double(b.height),
    ]))
}

print(jsonLine([
    "lines": sorted.count,
    "chars": totalChars,
    "coverage": totalArea,
    "mean_conf": confN > 0 ? confSum / Double(confN) : 0.0,
]))

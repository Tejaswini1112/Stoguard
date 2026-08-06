import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers
import AVFoundation
import PDFKit

// MARK: - Models

enum MediaKind: String, Codable, CaseIterable, Sendable {
    case image, video, document

    var label: String {
        switch self {
        case .image: return "Image"
        case .video: return "Video"
        case .document: return "Document"
        }
    }
}

enum MediaOptimizeMode: String, CaseIterable, Identifiable, Sendable {
    case losslessKeepResolution
    case targetSize

    var id: String { rawValue }

    var title: String {
        switch self {
        case .losslessKeepResolution: return "Optimize (keep resolution)"
        case .targetSize: return "Shrink to target size"
        }
    }

    var detail: String {
        switch self {
        case .losslessKeepResolution:
            return "Same pixel dimensions / frame size. Strips bulky metadata and recompresses efficiently. Never runs without your approval."
        case .targetSize:
            return "Keeps resolution when possible, lowers quality/bitrate until under your target (KB / MB / GB / TB)."
        }
    }
}

enum MediaSizeUnit: String, CaseIterable, Identifiable, Sendable {
    case kb = "KB"
    case mb = "MB"
    case gb = "GB"
    case tb = "TB"

    var id: String { rawValue }

    func toBytes(_ value: Double) -> Int64 {
        let mult: Double
        switch self {
        case .kb: mult = 1_000
        case .mb: mult = 1_000_000
        case .gb: mult = 1_000_000_000
        case .tb: mult = 1_000_000_000_000
        }
        return Int64(max(1, value * mult))
    }
}

struct MediaAsset: Identifiable, Hashable, Sendable {
    let id: String
    let path: String
    let name: String
    let kind: MediaKind
    let sizeBytes: Int64
    let pixelWidth: Int?
    let pixelHeight: Int?
    let note: String

    var sizeText: String { ByteText.string(sizeBytes) }
}

struct MediaOptimizeResult: Identifiable, Sendable {
    let id: String
    let path: String
    let beforeBytes: Int64
    let afterBytes: Int64
    let mode: MediaOptimizeMode
    let message: String

    var savedBytes: Int64 { max(0, beforeBytes - afterBytes) }
}

struct MediaOptimizePrompt: Identifiable, Sendable {
    let id = UUID()
    let assets: [MediaAsset]
    let mode: MediaOptimizeMode
    let targetBytes: Int64?
    var summary: String {
        let bytes = assets.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let modeText = mode == .targetSize
            ? "target \(ByteText.string(targetBytes ?? 0))"
            : "keep resolution"
        return "\(assets.count) file(s) · \(ByteText.string(bytes)) · \(modeText)"
    }
}

// MARK: - Scanner

enum MediaOptimizer {
    /// Default thresholds for “occupying a lot of space”.
    static let imageMinBytes: Int64 = 8_000_000      // 8 MB
    static let videoMinBytes: Int64 = 80_000_000     // 80 MB
    static let documentMinBytes: Int64 = 15_000_000  // 15 MB

    private static let imageExt: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "bmp", "webp", "gif",
    ]
    private static let videoExt: Set<String> = [
        "mp4", "mov", "m4v", "avi", "mkv", "mpg", "mpeg", "wmv",
    ]
    private static let docExt: Set<String> = [
        "pdf", "docx", "pptx", "xlsx", "key", "pages", "numbers", "zip", "psd", "ai",
    ]

    static func defaultRoots() -> [String] {
        let home = NSHomeDirectory()
        return [
            home + "/Downloads",
            home + "/Documents",
            home + "/Desktop",
            home + "/Pictures",
            home + "/Movies",
        ]
    }

    static func scan(
        roots: [String] = defaultRoots(),
        minImage: Int64 = imageMinBytes,
        minVideo: Int64 = videoMinBytes,
        minDocument: Int64 = documentMinBytes,
        limit: Int = 200
    ) -> [MediaAsset] {
        let fm = FileManager.default
        var out: [MediaAsset] = []
        for root in roots {
            guard fm.fileExists(atPath: root),
                  let enumerator = fm.enumerator(
                    at: URL(fileURLWithPath: root),
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isHiddenKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                  )
            else { continue }

            var visited = 0
            while let url = enumerator.nextObject() as? URL {
                visited += 1
                if visited > 25_000 { break }
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                let ext = url.pathExtension.lowercased()
                let kind: MediaKind?
                let minB: Int64
                if imageExt.contains(ext) { kind = .image; minB = minImage }
                else if videoExt.contains(ext) { kind = .video; minB = minVideo }
                else if docExt.contains(ext) { kind = .document; minB = minDocument }
                else { kind = nil; minB = 0 }
                guard let kind else { continue }
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? Shell.size(url.path)
                guard size >= minB else { continue }
                let dims = kind == .image ? imageDimensions(url) : nil
                out.append(MediaAsset(
                    id: url.path,
                    path: url.path,
                    name: url.lastPathComponent,
                    kind: kind,
                    sizeBytes: size,
                    pixelWidth: dims?.0,
                    pixelHeight: dims?.1,
                    note: note(for: kind, size: size, dims: dims)
                ))
                if out.count >= limit { break }
            }
            if out.count >= limit { break }
        }
        return out.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private static func note(for kind: MediaKind, size: Int64, dims: (Int, Int)?) -> String {
        switch kind {
        case .image:
            if let d = dims {
                return "\(d.0)×\(d.1) · optimize keeps these pixels"
            }
            return "Large image — optimize keeps resolution"
        case .video:
            return "Large video — optimize keeps frame size; lowers bitrate/metadata"
        case .document:
            return "Large document — recompress / strip extras when possible"
        }
    }

    private static func imageDimensions(_ url: URL) -> (Int, Int)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        else { return nil }
        let w = props[kCGImagePropertyPixelWidth] as? Int
        let h = props[kCGImagePropertyPixelHeight] as? Int
        if let w, let h { return (w, h) }
        return nil
    }

    // MARK: - Optimize (requires prior user approval)

    static func optimize(
        assets: [MediaAsset],
        mode: MediaOptimizeMode,
        targetBytes: Int64?
    ) async -> [MediaOptimizeResult] {
        var results: [MediaOptimizeResult] = []
        for asset in assets {
            let result = await optimizeOne(asset: asset, mode: mode, targetBytes: targetBytes)
            results.append(result)
        }
        return results
    }

    private static func optimizeOne(
        asset: MediaAsset,
        mode: MediaOptimizeMode,
        targetBytes: Int64?
    ) async -> MediaOptimizeResult {
        let before = asset.sizeBytes
        do {
            let after: Int64
            switch asset.kind {
            case .image:
                after = try optimizeImage(path: asset.path, mode: mode, targetBytes: targetBytes)
            case .video:
                after = try await optimizeVideo(path: asset.path, mode: mode, targetBytes: targetBytes)
            case .document:
                after = try optimizeDocument(path: asset.path, mode: mode, targetBytes: targetBytes)
            }
            let msg: String
            if after < before {
                msg = "Saved \(ByteText.string(before - after)) (now \(ByteText.string(after))). Original moved to Trash."
            } else {
                msg = "Already efficient — left unchanged (\(ByteText.string(before)))."
            }
            return MediaOptimizeResult(
                id: asset.id, path: asset.path, beforeBytes: before, afterBytes: after,
                mode: mode, message: msg
            )
        } catch {
            return MediaOptimizeResult(
                id: asset.id, path: asset.path, beforeBytes: before, afterBytes: before,
                mode: mode, message: "Skipped: \(error.localizedDescription)"
            )
        }
    }

    // MARK: Images — same pixel dimensions

    private static func optimizeImage(path: String, mode: MediaOptimizeMode, targetBytes: Int64?) throws -> Int64 {
        let url = URL(fileURLWithPath: path)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(src) > 0,
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { throw MediaOptimizeError.unreadable }

        let ext = url.pathExtension.lowercased()
        let utType: UTType = {
            switch ext {
            case "png": return .png
            case "heic", "heif": return .heic
            case "tif", "tiff": return .tiff
            default: return .jpeg
            }
        }()

        let qualities: [CGFloat] = {
            switch mode {
            case .losslessKeepResolution:
                // High quality / efficient container — resolution unchanged.
                return utType == .png ? [1.0] : [0.92, 0.88]
            case .targetSize:
                return [0.85, 0.7, 0.55, 0.4, 0.28, 0.18, 0.12]
            }
        }()

        let target = mode == .targetSize ? (targetBytes ?? (assetSize(path) / 2)) : nil
        var bestData: Data?
        var bestSize = assetSize(path)

        for q in qualities {
            let data = encodeImage(cg, type: utType, quality: q)
            guard let data, data.count > 0 else { continue }
            if data.count < bestSize {
                bestData = data
                bestSize = Int64(data.count)
            }
            if let target, Int64(data.count) <= target {
                bestData = data
                bestSize = Int64(data.count)
                break
            }
            if mode == .losslessKeepResolution { break }
        }

        guard let bestData, bestSize < assetSize(path) else {
            return assetSize(path)
        }
        try replaceWithBackupToTrash(original: path, newData: bestData)
        return assetSize(path)
    }

    private static func encodeImage(_ image: CGImage, type: UTType, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            return nil
        }
        let props: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
        ]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    // MARK: Video — keep frame size, adjust bitrate

    private static func optimizeVideo(path: String, mode: MediaOptimizeMode, targetBytes: Int64?) async throws -> Int64 {
        // Prefer ffmpeg when available (same scale, CRF / target size).
        if let after = try? await ffmpegOptimize(path: path, mode: mode, targetBytes: targetBytes) {
            return after
        }
        return try await avExportOptimize(path: path, mode: mode, targetBytes: targetBytes)
    }

    private static func ffmpegOptimize(path: String, mode: MediaOptimizeMode, targetBytes: Int64?) async throws -> Int64 {
        guard let ffmpeg = which("ffmpeg") else { throw MediaOptimizeError.toolMissing }
        let before = assetSize(path)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("stoguard-vid-\(UUID().uuidString).mp4")
        var args = ["-y", "-i", path, "-vf", "scale=iw:ih", "-c:v", "libx264", "-c:a", "aac", "-movflags", "+faststart"]
        switch mode {
        case .losslessKeepResolution:
            args += ["-crf", "23", "-preset", "medium"]
        case .targetSize:
            let target = max(targetBytes ?? (before / 2), 500_000)
            // Rough bitrate from target size / duration; fallback CRF ladder.
            args += ["-fs", "\(target)", "-crf", "28", "-preset", "medium"]
        }
        args.append(tmp.path)
        try run(ffmpeg, args: args, timeout: 600)
        let newSize = assetSize(tmp.path)
        guard newSize > 0, newSize < before else {
            try? FileManager.default.removeItem(at: tmp)
            return before
        }
        let data = try Data(contentsOf: tmp)
        try? FileManager.default.removeItem(at: tmp)
        // Keep .mp4 extension for compatibility when replacing mov/etc.
        let destExt = (path as NSString).pathExtension.lowercased()
        if destExt == "mp4" || destExt == "m4v" || destExt == "mov" {
            try replaceWithBackupToTrash(original: path, newData: data)
        } else {
            // Write sibling .mp4 and trash original
            let sibling = (path as NSString).deletingPathExtension + ".mp4"
            try data.write(to: URL(fileURLWithPath: sibling), options: .atomic)
            _ = try? trash(path)
        }
        return assetSize(path)
    }

    private static func avExportOptimize(path: String, mode: MediaOptimizeMode, targetBytes: Int64?) async throws -> Int64 {
        let before = assetSize(path)
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)
        // Prefer presets that do not force a smaller frame size.
        let preset: String = {
            switch mode {
            case .losslessKeepResolution:
                return AVAssetExportPresetHighestQuality
            case .targetSize:
                if let t = targetBytes, t < before / 3 {
                    return AVAssetExportPresetMediumQuality
                }
                return AVAssetExportPresetHighestQuality
            }
        }()
        let usePreset = AVAssetExportSession.allExportPresets().contains(preset)
            ? preset : AVAssetExportPresetHighestQuality
        guard let session = AVAssetExportSession(asset: asset, presetName: usePreset) else {
            throw MediaOptimizeError.unreadable
        }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("stoguard-av-\(UUID().uuidString).mp4")
        session.outputURL = tmp
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        await session.export()
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: tmp)
            throw MediaOptimizeError.exportFailed(session.error?.localizedDescription ?? "export")
        }
        let newSize = assetSize(tmp.path)
        guard newSize > 0, newSize < before else {
            try? FileManager.default.removeItem(at: tmp)
            return before
        }
        let data = try Data(contentsOf: tmp)
        try? FileManager.default.removeItem(at: tmp)
        try replaceWithBackupToTrash(original: path, newData: data)
        return assetSize(path)
    }

    // MARK: Documents

    private static func optimizeDocument(path: String, mode: MediaOptimizeMode, targetBytes: Int64?) throws -> Int64 {
        let ext = (path as NSString).pathExtension.lowercased()
        let before = assetSize(path)
        if ext == "pdf" {
            return try optimizePDF(path: path, mode: mode, targetBytes: targetBytes, before: before)
        }
        // Zip-based office docs: recompress with max compression if we can shrink.
        if ["docx", "pptx", "xlsx", "zip"].contains(ext) {
            return try recompressZip(path: path, before: before)
        }
        throw MediaOptimizeError.unsupported
    }

    private static func optimizePDF(path: String, mode: MediaOptimizeMode, targetBytes: Int64?, before: Int64) throws -> Int64 {
        guard let doc = PDFDocument(url: URL(fileURLWithPath: path)) else {
            throw MediaOptimizeError.unreadable
        }
        // Rewrite PDF (often drops incremental junk). Resolution of embedded images unchanged here.
        guard let data = doc.dataRepresentation() else { throw MediaOptimizeError.unreadable }
        if data.count >= before { return before }
        if mode == .targetSize, let t = targetBytes, data.count > t {
            // Can't losslessly hit target — still apply rewrite savings and report.
        }
        try replaceWithBackupToTrash(original: path, newData: data)
        return assetSize(path)
    }

    private static func recompressZip(path: String, before: Int64) throws -> Int64 {
        // Use ditto/zip if available for a recompressed copy.
        guard let ditto = which("ditto") else { throw MediaOptimizeError.toolMissing }
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("stoguard-zip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let extract = tmpDir.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: extract, withIntermediateDirectories: true)
        try run(ditto, args: ["-x", "-k", path, extract.path], timeout: 180)
        let outZip = tmpDir.appendingPathComponent("out.zip")
        try run(ditto, args: ["-c", "-k", "--sequesterRsrc", extract.path, outZip.path], timeout: 180)
        let newSize = assetSize(outZip.path)
        guard newSize > 0, newSize < before else { return before }
        let data = try Data(contentsOf: outZip)
        try replaceWithBackupToTrash(original: path, newData: data)
        return assetSize(path)
    }

    // MARK: Helpers

    private static func assetSize(_ path: String) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value
            ?? Shell.size(path)
    }

    private static func replaceWithBackupToTrash(original: String, newData: Data) throws {
        // Write optimized bytes to a temp file first, then trash the original and move into place.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("stoguard-opt-\(UUID().uuidString)")
        try newData.write(to: tmp, options: .atomic)
        try trash(original)
        try FileManager.default.moveItem(at: tmp, to: URL(fileURLWithPath: original))
    }

    private static func trash(_ path: String) throws {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &resulting)
    }

    private static func which(_ cmd: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = [cmd]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }
        proc.waitUntilExit()
        let s = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    private static func run(_ launch: String, args: [String], timeout: TimeInterval) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launch)
        proc.arguments = args
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        try proc.run()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            proc.waitUntilExit()
            group.leave()
        }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            proc.terminate()
            throw MediaOptimizeError.timeout
        }
        if proc.terminationStatus != 0 {
            throw MediaOptimizeError.exportFailed("tool exit \(proc.terminationStatus)")
        }
    }
}

enum MediaOptimizeError: LocalizedError {
    case unreadable, unsupported, toolMissing, timeout, exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadable: return "Could not read file"
        case .unsupported: return "This document type isn’t optimizable yet"
        case .toolMissing: return "Required tool not found"
        case .timeout: return "Optimization timed out"
        case .exportFailed(let s): return "Export failed: \(s)"
        }
    }
}

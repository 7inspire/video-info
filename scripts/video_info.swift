#!/usr/bin/env swift

import AVFoundation
import Foundation

guard CommandLine.arguments.count > 1 else {
    fputs("用法: video_info <视频文件路径>\n", stderr)
    exit(1)
}

let filePath = CommandLine.arguments[1]
let url = URL(fileURLWithPath: filePath)

// 检查文件是否存在
guard FileManager.default.fileExists(atPath: filePath) else {
    fputs("错误: 文件不存在 - \(filePath)\n", stderr)
    exit(1)
}

// 文件名
let filename = url.lastPathComponent

// 文件大小
func formatFileSize(_ bytes: UInt64) -> String {
    let gb = Double(bytes) / 1_073_741_824
    let mb = Double(bytes) / 1_048_576
    let kb = Double(bytes) / 1024
    if gb >= 1.0 {
        return String(format: "%.2f GB", gb)
    } else if mb >= 1.0 {
        return String(format: "%.2f MB", mb)
    } else if kb >= 1.0 {
        return String(format: "%.2f KB", kb)
    } else {
        return "\(bytes) B"
    }
}

var fileSize = "无法获取"
if let attrs = try? FileManager.default.attributesOfItem(atPath: filePath),
   let size = attrs[.size] as? UInt64 {
    fileSize = formatFileSize(size)
}

// 使用 AVFoundation 获取视频信息
let asset = AVURLAsset(url: url)
let semaphore = DispatchSemaphore(value: 0)

var resolution = "无法获取"
var fps = "无法获取"
var codec = "无法获取"
var colorInfo = "无法获取"
var durationStr = "无法获取"
var bitrate = "无法获取"

asset.loadValuesAsynchronously(forKeys: ["tracks", "duration"]) {
    // 时长
    let duration = asset.duration
    let seconds = CMTimeGetSeconds(duration)
    if seconds.isFinite && seconds > 0 {
        let totalSec = Int(seconds)
        let hours = totalSec / 3600
        let minutes = (totalSec % 3600) / 60
        let secs = totalSec % 60
        if hours > 0 {
            durationStr = String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            durationStr = String(format: "%d:%02d", minutes, secs)
        }
        durationStr += String(format: " (%.1f 秒)", seconds)
    }

    // 视频轨道信息
    let videoTracks = asset.tracks(withMediaType: .video)
    if let track = videoTracks.first {
        // 分辨率（考虑旋转）
        let size = track.naturalSize
        let transform = track.preferredTransform
        let w = abs(size.width * transform.a) + abs(size.height * transform.c)
        let h = abs(size.width * transform.b) + abs(size.height * transform.d)
        let width = Int(w)
        let height = Int(h)
        resolution = "\(width) × \(height)"

        // 码率
        let estimatedBitRate = track.estimatedDataRate
        if estimatedBitRate > 0 {
            let mbps = estimatedBitRate / 1_000_000
            let kbps = estimatedBitRate / 1_000
            if mbps >= 1.0 {
                bitrate = String(format: "%.2f Mbps", mbps)
            } else {
                bitrate = String(format: "%.0f Kbps", kbps)
            }
        }

        // 帧率
        let nominalFPS = track.nominalFrameRate
        if nominalFPS > 0 {
            if nominalFPS == Float(Int(nominalFPS)) {
                fps = "\(Int(nominalFPS)) fps"
            } else {
                fps = String(format: "%.2f fps", nominalFPS)
            }
        }

        // 编码格式和色彩信息
        let descriptions = track.formatDescriptions as! [CMFormatDescription]
        if let desc = descriptions.first {
            // 编码格式
            let codecType = CMFormatDescriptionGetMediaSubType(desc)
            let bytes: [UInt8] = [
                UInt8((codecType >> 24) & 0xFF),
                UInt8((codecType >> 16) & 0xFF),
                UInt8((codecType >> 8) & 0xFF),
                UInt8(codecType & 0xFF)
            ]
            let codecFourCC = String(bytes: bytes, encoding: .ascii) ?? "Unknown"

            // 映射常见编码名称
            let codecNames: [String: String] = [
                "avc1": "H.264 (AVC)",
                "hvc1": "H.265 (HEVC)",
                "hev1": "H.265 (HEVC)",
                "av01": "AV1",
                "vp09": "VP9",
                "mp4v": "MPEG-4",
                "ap4h": "Apple ProRes 4444",
                "ap4x": "Apple ProRes 4444 XQ",
                "apch": "Apple ProRes 422 HQ",
                "apcn": "Apple ProRes 422",
                "apcs": "Apple ProRes 422 LT",
                "apco": "Apple ProRes 422 Proxy",
            ]
            codec = codecNames[codecFourCC] ?? codecFourCC

            // 色彩信息
            if let extensions = CMFormatDescriptionGetExtensions(desc) as? [String: Any] {
                var colorParts: [String] = []

                if let primaries = extensions["ColorPrimaries"] as? String {
                    let primariesMap: [String: String] = [
                        "ITU_R_709_2": "BT.709",
                        "ITU_R_2020": "BT.2020",
                        "P3_D65": "Display P3",
                        "SMPTE_C": "SMPTE-C",
                    ]
                    colorParts.append(primariesMap[primaries] ?? primaries)
                }

                if let transfer = extensions["TransferFunction"] as? String {
                    let transferMap: [String: String] = [
                        "ITU_R_709_2": "BT.709",
                        "SMPTE_ST_2084_PQ": "HDR (PQ)",
                        "ITU_R_2100_HLG": "HDR (HLG)",
                        "IEC_sRGB": "sRGB",
                    ]
                    colorParts.append(transferMap[transfer] ?? transfer)
                }

                if let matrix = extensions["YCbCrMatrix"] as? String {
                    let matrixMap: [String: String] = [
                        "ITU_R_709_2": "BT.709",
                        "ITU_R_2020": "BT.2020",
                        "ITU_R_601_4": "BT.601",
                    ]
                    colorParts.append("Matrix: \(matrixMap[matrix] ?? matrix)")
                }

                if let depth = extensions["BitsPerComponent"] as? Int {
                    colorParts.append("\(depth)-bit")
                } else if let depth = extensions["Depth"] as? Int {
                    colorParts.append("\(depth)-bit")
                }

                if !colorParts.isEmpty {
                    colorInfo = colorParts.joined(separator: " / ")
                }
            }
            
            // 如果没有从扩展中获取到色彩信息，尝试从 mdls 获取
            if colorInfo == "无法获取" {
                // 尝试通过像素格式推断
                let pixelFormat = CMFormatDescriptionGetMediaSubType(desc)
                // 常见像素格式对应的位深
                switch pixelFormat {
                case 0x68766331, 0x68657631: // hvc1, hev1 - HEVC 通常支持 10-bit
                    colorInfo = "SDR (推测)"
                default:
                    break
                }
            }
        }
    }

    semaphore.signal()
}

// 等待最多 10 秒
let result = semaphore.wait(timeout: .now() + 10)
if result == .timedOut {
    fputs("警告: 获取视频信息超时\n", stderr)
}

// 输出结果
let info = """
📁 文件名：\(filename)
📐 分辨率：\(resolution)
🎞 帧率：\(fps)
🎬 编码格式：\(codec)
📊 码率：\(bitrate)
🎨 色彩信息：\(colorInfo)
⏱ 时长：\(durationStr)
💾 文件大小：\(fileSize)
"""

print(info)

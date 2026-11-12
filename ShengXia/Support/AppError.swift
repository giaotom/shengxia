import Foundation

enum AppError: LocalizedError {
    case cancelled
    case downloadFailed(String)
    case notMedia
    case noAudioTrack
    case exportFailed
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "已取消"
        case .downloadFailed(let message):
            return message
        case .notMedia:
            return "下载到的不是音频或视频文件"
        case .noAudioTrack:
            return "这条视频没有音轨"
        case .exportFailed:
            return "提取音轨失败"
        case .saveFailed(let message):
            return "保存失败：\(message)"
        }
    }
}

import Foundation

public enum ResolveError: Error, Equatable, LocalizedError, Sendable {
    case emptyInput
    case unsupportedLink
    case bilibiliBanned
    case bilibiliNotFound
    case bilibiliHidden
    case bilibiliNoAudio
    case bilibiliFLVOnly
    case bilibiliVipBlocked
    case bilibiliLiveUnsupported
    case bilibiliBangumiUnsupported
    case bilibiliCheeseUnsupported
    case bilibiliMessage(String)
    case douyinLiveUnsupported
    case douyinNoVideoID
    case douyinNotAVideo
    case douyinImagePost
    case douyinResolveFailed
    case douyinWrongVideo
    case network(String)
    case badResponse(String)

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "请先粘贴链接"
        case .unsupportedLink:
            return "暂时只支持哔哩哔哩和抖音的视频链接"
        case .bilibiliBanned:
            return "哔哩哔哩拒绝了请求，请稍后再试"
        case .bilibiliNotFound:
            return "视频不存在或已被删除"
        case .bilibiliHidden:
            return "稿件不可见"
        case .bilibiliNoAudio:
            return "没有找到可下载的音频流"
        case .bilibiliFLVOnly:
            return "该视频只剩 FLV 流，iPhone 无法从中提取音轨"
        case .bilibiliVipBlocked:
            return "该内容需要大会员，声匣不会绕过付费墙"
        case .bilibiliLiveUnsupported:
            return "暂不支持哔哩哔哩直播"
        case .bilibiliBangumiUnsupported:
            return "暂不支持番剧链接，请换普通视频"
        case .bilibiliCheeseUnsupported:
            return "这是付费课程，声匣不会绕过付费墙"
        case .bilibiliMessage(let message):
            return message
        case .douyinLiveUnsupported:
            return "暂不支持抖音直播"
        case .douyinNoVideoID:
            return "没有在这段分享里找到抖音视频"
        case .douyinNotAVideo:
            return "这不是抖音视频链接"
        case .douyinImagePost:
            return "这条抖音是图文，没有可提取的视频音轨"
        case .douyinResolveFailed:
            return "抖音解析失败，可能是抖音更新了校验"
        case .douyinWrongVideo:
            return "抖音打开了别的视频，已停止保存"
        case .network(let message):
            return "网络出错：\(message)"
        case .badResponse(let message):
            return message
        }
    }
}

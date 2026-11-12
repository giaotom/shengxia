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
    case youtubeConnectionFailed
    case youtubeResolveFailed
    case youtubeAgeRestricted
    case youtubePrivate
    case youtubeMembersOnly
    case youtubeUnavailable
    case youtubeRegionBlocked
    case youtubeNoAudio
    case youtubeLiveUnsupported
    case youtubeNotAVideo
    case network(String)
    case badResponse(String)

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "请先粘贴链接"
        case .unsupportedLink:
            return "暂时只支持哔哩哔哩、抖音和 YouTube 的视频链接"
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
        case .youtubeConnectionFailed:
            return "YouTube 连接失败，请确认手机已开启代理"
        case .youtubeResolveFailed:
            return "YouTube 解析失败，可能是风控更新"
        case .youtubeAgeRestricted:
            return "这个视频有年龄限制，声匣不会绕过登录验证"
        case .youtubePrivate:
            return "这个视频是私密的，无法提取"
        case .youtubeMembersOnly:
            return "这个视频仅限频道会员，声匣不会绕过会员墙"
        case .youtubeUnavailable:
            return "视频不存在或已被删除"
        case .youtubeRegionBlocked:
            return "这个视频在当前地区不可用"
        case .youtubeNoAudio:
            return "没有找到 iPhone 能播放的 AAC 音轨"
        case .youtubeLiveUnsupported:
            return "暂不支持 YouTube 直播"
        case .youtubeNotAVideo:
            return "没有在这段链接里找到 YouTube 视频"
        case .network(let message):
            return "网络出错：\(message)"
        case .badResponse(let message):
            return message
        }
    }
}

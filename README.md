# 声匣

给 Tom 自己用的 iPhone 音轨匣。粘贴哔哩哔哩或抖音的**公开视频**链接，在手机上解析、下载整条音轨，存进本机资料库播放。没有服务器，没有账号，也不会绕过大会员或任何付费墙，也不做人声分离。

界面是简体中文。系统要求 iOS 16 及以上（在 iPhone 15 Pro 上使用）。

## 能做什么

- **哔哩哔哩**：完整链接、`b23.tv` 短链、单独的 BV 号，以及带 `?p=` 的分 P。先向公开接口要 `buvid`，再取稿件信息和 DASH 音频流（`fnval=16`），带上 Referer 和浏览器 User-Agent 下载。优先最高码率的 AAC；有 FLAC 就存 FLAC。杜比音轨会跳过。只剩 FLV 时会说明 iPhone 解不了。
- **抖音**：分享文案、`v.douyin.com` 短链、视频页链接。先跟随跳转拿到视频号，再试分享页和公开的 `iteminfo`。这些接口现在经常不再返回播放地址，这时会在 App 里打开抖音网页（不登录），等页面自己请求到视频地址后再下载，并用系统的 AVFoundation 抽出音轨。
- 格式标清楚。iPhone 没有系统自带的 MP3 编码器，所以新保存的音轨是 **M4A（AAC）** 或源站给出的 **FLAC**。你放进文件夹的 MP3 会保持 MP3。
- 资料库：封面、播放/暂停、上一首/下一首、拖动进度、随机、循环、删除。
- 后台播放和锁屏控制（`AVAudioSession.playback`、`UIBackgroundModes: audio`、Now Playing、远程命令）。
- 「文件」App 里能看到 `声匣/Music`。把 mp3、m4a、flac 放进去，回到声匣下拉即可收进资料库。

## 在 Mac 上编译未签名 IPA

需要 Xcode 15 或更新，以及 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```bash
brew install xcodegen
xcodegen generate
xcodebuild \
  -project ShengXia.xcodeproj \
  -scheme ShengXia \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -sdk iphoneos \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" \
  build
APP=build/Build/Products/Release-iphoneos/ShengXia.app
rm -rf Payload && mkdir Payload && cp -R "$APP" Payload/
zip -qry ShengXia-unsigned.ipa Payload
```

纯逻辑测试不需要 Mac：

```bash
swift test --package-path Packages/ShengXiaCore
```

仓库里的 `.github/workflows/build-ipa.yml` 会在 `macos-latest` 上做同样的事，并把 `ShengXia-unsigned.ipa` 传到 Actions 构件。推到 `main` 或在 Actions 页手动运行即可。

## 用 Windows 装到 iPhone（Sideloadly + 免费 Apple ID）

未签名的 IPA 不能直接装。Sideloadly 会用你的 Apple ID 重新签名。免费 Apple ID 的描述文件大约 **7 天**过期，过期后要再签一次。

1. 从 [sideloadly.io](https://sideloadly.io) 安装 Sideloadly。
2. 安装微软商店里的「Apple 设备」，或安装 iTunes，好让电脑有 Apple Mobile Device 驱动。
3. 用数据线连接 iPhone 15 Pro，在手机上点「信任」。
4. 打开 Sideloadly，用免费 Apple ID 登录。开了双重认证的话，到 [appleid.apple.com](https://appleid.apple.com) 生成 App 专用密码，不要把主密码填进去。
5. 把 `ShengXia-unsigned.ipa` 拖进去。Bundle ID 可以保持 `com.giaotom.shengxia`。点 Start。
6. iOS 16 及以上要打开开发者模式：设置 → 隐私与安全性 → 开发者模式，按提示重启。
7. 设置 → 通用 → VPN 与设备管理，信任这个 Apple ID 的证书。
8. 打开「声匣」。快到第 7 天时再插上电脑，用 Sideloadly 重新安装或刷新。免费账号同时大概只能挂着很少的自签 App，个人用足够。
9. 锁屏控制：开始播放后按电源键即可，不要把 App 从后台划掉。
10. 自己的文件：文件 App → 浏览 → 我的 iPhone → 声匣 → Music。

## 抖音为什么不稳

2026 年 11 月实测，抖音分享页的 `window._ROUTER_DATA` 里已经没有 `videoInfoRes` / `play_addr`。`iteminfo` 匿名请求经常是空 body，详情接口会要页面自己生成的校验。声匣不会去伪造这套签名。它只做两件事：能从公开数据里直接读到地址就下载；读不到就打开抖音自己的网页，把页面要到的视频地址接下来。抖音一改页面，就会看到「抖音解析失败，可能是抖音更新了校验」。图文作品没有视频音轨，会直接说明，不会去扒背景音乐。

## 这次没能交出的东西

这台构建环境是 Linux，没有 Xcode，也没有登录到 `giaotom` 的 GitHub，所以这里**没有**生成 IPA，也没办法替你在私人仓库里跑 macOS 工作流。把这个仓库推到你自己的私人 GitHub 仓库并打开 Actions 之后，构件里会出现 `ShengXia-unsigned.ipa`。

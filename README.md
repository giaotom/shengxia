# 声匣

给 Tom 自己用的 iPhone 音轨匣，版本 2.0。粘贴哔哩哔哩、抖音或 YouTube 的**公开视频**链接，在手机上解析、下载整条音轨，存进本机资料库播放。没有服务器，没有账号，也不会绕过大会员、会员专享或年龄限制，也不做人声分离。

界面是简体中文。系统要求 iOS 16 及以上。iOS 26 用系统的 Liquid Glass（悬浮玻璃标签栏、玻璃按钮）；iOS 16 到 25 用同样的布局，材质换成半透明磨砂。

2.0 在三个标签里：**提取**（打开就是这一页）、**资料库**、**歌单**。设置在右上角。资料库可以搜索、按来源筛选、看喜欢的。歌单能新建、改名、删除、加减和排序。播放页有队列、定时、倍速、A-B 循环、喜欢、随机和循环，没有歌词，也没有 AirPlay。还可以剪一段存成新音轨、改标题和封面、批量提取、自动去静音、响度对齐，以及发现同一条视频已经存过。分享菜单里的「声匣」会打开 `shengxia://extract?text=`；这个扩展不依赖 App Group。

## 能做什么

- **哔哩哔哩**：完整链接、`b23.tv` 短链、单独的 BV 号，以及带 `?p=` 的分 P。先向公开接口要 `buvid`，再取稿件信息和 DASH 音频流（`fnval=16`），带上 Referer 和浏览器 User-Agent 下载。优先最高码率的 AAC；有 FLAC 就存 FLAC。杜比音轨会跳过。只剩 FLV 时会说明 iPhone 解不了。
- **抖音**：分享文案、`v.douyin.com` 短链、视频页链接。先跟随跳转拿到视频号，再试分享页和公开的 `iteminfo`。这些接口现在经常不再返回播放地址，这时会在 App 里打开抖音网页（不登录），等页面自己请求到视频地址后再下载，并用系统的 AVFoundation 抽出音轨。
- **YouTube**：`watch?v=`、`youtu.be`、`/shorts/`、`m.youtube.com`、`music.youtube.com`，以及夹在分享文案里的链接。手机直接请求 InnerTube `/youtubei/v1/player`（VISIONOS，失败再试 ANDROID_VR 1.65.10 和 iOS），只要返回没加密的音频地址就下载。优先 AAC itag 140，存成 M4A。不解签名，也不做 PO Token。私密、会员专享和年龄限制会直接说明，不会绕过。连不上时提示检查代理；只返回风控页时提示解析失败。WebM/Opus 在 iPhone 上播不了，所以不会拿它当结果。
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

仓库里的 `.github/workflows/build-ipa.yml` 会在 `macos-26-intel` 上做同样的事，并把 `ShengXia-unsigned.ipa` 传到 Actions 构件。推到 `main` 或在 Actions 页手动运行即可。

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
10. 自己的文件：文件 App → 浏览 → 我的 iPhone → 声匣 → Music。备份的歌单信息在「声匣 / 备份」。
11. 分享扩展：IPA 里带了一个「声匣」分享按钮，不需要 App Group。免费 Apple ID 有时签不上扩展，Sideloadly 可能因此整包失败。真失败的话，用快捷指令打开 `shengxia://extract?text=` 加上链接，主功能不靠这个扩展。

## 抖音为什么不稳

2026 年 11 月实测，抖音分享页的 `window._ROUTER_DATA` 里已经没有 `videoInfoRes` / `play_addr`。`iteminfo` 匿名请求经常是空 body，详情接口会要页面自己生成的校验。声匣不会去伪造这套签名。它只做两件事：能从公开数据里直接读到地址就下载；读不到就打开抖音自己的网页，把页面要到的视频地址接下来。抖音一改页面，就会看到「抖音解析失败，可能是抖音更新了校验」。图文作品没有视频音轨，会直接说明，不会去扒背景音乐。

## YouTube 为什么会失败

2026 年 11 月，VISIONOS 客户端对一部分公开视频仍会返回可直接下载的 AAC（itag 140），整段文件可以下完。同一出口上，另一些视频会得到 `LOGIN_REQUIRED` / “Sign in to confirm you're not a bot”，声匣不会去伪造 PO Token，而是换 ANDROID_VR 和 iOS 再试一次，还不行就提示「YouTube 解析失败，可能是风控更新」。手机在国内打不开 YouTube 时，提示「YouTube 连接失败，请确认手机已开启代理」。

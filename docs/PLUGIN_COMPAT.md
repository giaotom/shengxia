# 插件核对

核对时间：2026-11-13。

这台机器是 Linux，没有 iPhone 模拟器，也没有 JavaScriptCore。下面的「通过 / 没通过」不是在声匣 App 里点出来的，也没有截图。跑法是：用和 App 里同一份 `Linker.js` 把插件收成脚本，在 Node 22 里执行；`host.crypto` 用的是 Node 的 MD5 和 AES-ECB（PKCS7）；网络用的是 Node 的 `fetch`。单元测试会在 macOS 的 JavaScriptCore 上跑引擎本身（打包、Promise、超时、隔离、`fetch` 权限），不替这些网站做一次真机播放。

「通过」表示这次至少有一条结果返回了音频地址，并且对这个地址做了带 Range 的请求，状态是 200 或 206，类型是音频。没拿到字节的，一律不算通过，也不放进 App 里的目录。目录之外的仓库仍然可以自己贴地址安装。

## 放进目录

| 仓库 | 插件 | 结果 |
| --- | --- | --- |
| [hubandad/mygo-music-netease](https://github.com/hubandad/mygo-music-netease) | netease 1.0.0 | 搜索「晴天」有结果。原唱提示没有完整播放权限。同一次结果里的《晴天（弦乐版）》返回 mp3，`206 audio/mpeg`。 |
| [AkinoKaede/mygo-music-netease-cloud-music](https://github.com/AkinoKaede/mygo-music-netease-cloud-music) | netease-cloud-music 0.1.13 | 默认分支是 TypeScript，根目录没有 `index.js`。装的是 Release `v0.1.13` 的 zip。同样是弦乐版拿到 mp3，`206`。和上一只 `id` 都是 `netease`，声匣会分成两个。 |
| [dddaniel1/mygo-plugin-qqmusic](https://github.com/dddaniel1/mygo-plugin-qqmusic) | qqmusic 0.2.4 | 《晴天》（周杰伦）未登录拿到 mp3，`206 audio/mpeg`，主机 `aqqmusic.tc.qq.com`。 |
| [Lorpaves/mygo-music-qqmusic](https://github.com/Lorpaves/mygo-music-qqmusic) | qqmusic 0.3.4 | 入口是 `dist/index.js`。原曲《晴天》要求登录。同一次结果里的《晴天（超盛大弦乐）》拿到 mp3，`206`。 |
| [dddaniel1/mygo-plugin-kugou](https://github.com/dddaniel1/mygo-plugin-kugou) | kugou 0.1.0 | 第一条《晴天》要求登录。下一条同名结果拿到 mp3，`206 audio/mpeg`。 |
| [bitbyte404/mygo-music-kugou-lite](https://github.com/bitbyte404/mygo-music-kugou-lite) | kugou-lite 1.3.2 | 和上面类似：第一条要登录，第二条《晴天》拿到 mp3，`206`。设置里的每日 VIP 是插件自己的开关，这次没有去打开它，也没有另外写会员逻辑。 |
| [amqsy/mygo-music-bodian](https://github.com/amqsy/mygo-music-bodian) | bodian 0.3.2 | 前几条《晴天》被拒绝（其中一条是 407）。后面一条同名结果拿到 mp3，`206 audio/mpeg`。 |
| [GentleM4dman/mygo-music-bilibili](https://github.com/GentleM4dman/mygo-music-bilibili) | bilibili 0.4.2 | 搜索「晴天」后，标准音质直接返回 m4a，`206`，主机 `bilivideo.com`。这次没有调用 `host.spawn`。插件声明了 ffmpeg，声匣拒绝启动外部程序，所以要转码的音质不会播。 |
| [popeyelau/mygo-queyue](https://github.com/popeyelau/mygo-queyue) | mygo-queyue 0.1.0 | 搜索直接要求登录。未登录调用 `home()`，每日推荐里的 *Yes OK* 拿到 mp3，`206 audio/mpeg`，主机 `cdn2.indie.cn`。 |
| [djyde/mygo-lizhi](https://github.com/djyde/mygo-lizhi) | lizhi 1.1.0 | 搜索「天空」。《天空之城》拿到 mp3，`206`，主机 `testingcf.jsdelivr.net`。不用登录。 |
| [GYRYEZ/mygo-music-roamdial](https://github.com/GYRYEZ/mygo-music-roamdial) | roamdial 0.1.0 | 搜索「bbc」。*BBC UNHCR* 的直播流返回 `200 audio/mpeg`，主机 `stream.live.vc.bbcmedia.co.uk`。这是电台，不是曲库。 |

## 没有放进目录

| 仓库 | 原因 |
| --- | --- |
| [sogud/mygo-music-netease](https://github.com/sogud/mygo-music-netease) | 搜索「晴天」有 30 条。抽了前 6 条，播放要么是「无完整播放权限」，要么是网易云 `-460`（网络环境风险）。没有一条拿到音频。 |
| [Maker-World/mygo-music-migu](https://github.com/Maker-World/mygo-music-migu) | 搜索有结果。抽了 6 条，咪咕都返回版权地区限制（440001，「该内容暂无法在当前地区提供服务」）。没有音频。 |
| [specialhua/mygo-ximalaya](https://github.com/specialhua/mygo-ximalaya) | 能搜到节目《趣谈郭德纲》。打开单集后，播放接口返回「喜马拉雅接口暂不可用（927）」。没有音频。 |
| [shensl4499/mygo-music-xiaoyuzhou](https://github.com/shensl4499/mygo-music-xiaoyuzhou) | 搜索要求先连接账号。未登录的首页只有「连接账号」，没有可播单集。 |

哔哩哔哩那只虽然声明了 ffmpeg，标准音质并不依赖它，所以留在目录里，并在说明里写了限制。

## 这次没做的事

没有 iOS 模拟器，所以没有插件页和搜索结果的截图。不要把上面的 HTTP 状态看成手机上已经播出来了。真机还要再看插件页、钥匙串和 `AVPlayer` 是否接受这些地址。

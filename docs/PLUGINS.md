# 声匣插件接口

目录里的插件来自 [MyGo Music](https://github.com/egoist/mygo-music)。一只插件是一个文件夹：`plugin.json` 加上一个 ES module。声匣在 iPhone 的 JavaScriptCore 里跑它。JavaScriptCore 不认识 `import` / `export`，所以安装之后会把相对导入收成一个脚本，再执行。

MusicFree 是另一套接口（`module.exports`，方法名叫 `search`、`getMediaSource`）。声匣也接受这种脚本：`require("axios")`、`crypto-js`、`dayjs`、`he`、`qs`、`big-integer` 可以用，`cheerio` 和 `webdav` 只有一小部分。目录里的仓库都不是这套写法，下面记的是它们真正调用的 MyGo 接口。

## plugin.json

声匣会读：

- `id`、`name`、`version`、`description`、`main`
- `permissions.network`：可以请求的主机。`*.qq.com` 这种后缀也可以。没有列出的主机，`fetch` 会直接失败。
- `settings`：`key`、`label`、`help`。用户在插件页填写，插件用 `host.setting(key)` 读取。

两只插件可以有同一个 `id`。后安装的那只会用 `id@作者` 分开存放。

GitHub 仓库会先找最新 Release 里的通用 zip（跳过带 darwin、windows、linux、macos 的文件名），没有再下默认分支的源码包。源码还是 TypeScript、没有 `main` 指向的文件时，安装会说明原因，不会假装装上了。

## 插件导出的函数

函数名就是能力。参数是一个对象，可以返回值，也可以返回 Promise。声匣把参数和结果按 JSON 交接。

| 函数 | 声匣会怎么用 |
| --- | --- |
| `search({query, kind, offset})` | 搜索。`kind` 用 `"tracks"`。读返回里的 `tracks`，没有再看 `shows` 和 `playlists`。 |
| `stream({id, quality})` | 播放和保存。先试用户在设置里填的音质，再按 standard、high、128、320、flac、higher、exhigh、lossless、hires、low 往下试，直到有 `url`。 |
| `lyrics({id})` | 有 `lrc` 就用。否则把 `lines[].text` 拼成文本，放在播放页的更多菜单里。 |
| `playlist({id})` | 导入歌单。最多保存 12 首到一个新的声匣歌单。 |
| `home()` | 插件页的「首页」。用来给没有登录就搜不了、但首页有公开内容的插件。 |

`stream` 要返回 `{url, type, quality, headers}`。`headers` 会交给播放器和下载。曲目的 `duration` 按毫秒理解。

保存进资料库时，显示名走原来的 10 字规则，只作用于新保存的那一条。文件名仍用完整标题。已经在资料库里的音轨不会因为装了插件被改名。

## host

| 成员 | 行为 |
| --- | --- |
| `platform` / `arch` | `"ios"` 和 `"arm64"` |
| `dir` / `dataDir` | 这只插件自己的目录 |
| `language()` | `"zh-CN"` |
| `t(text)` | 读插件的 `locales/zh-CN.json`，没有就原样返回 |
| `setting(key)` | 用户填的设置，没有就空字符串 |
| `storage.get/set/remove` | JSON。cookie 和令牌优先放钥匙串；钥匙串不可用时写在 Application Support |
| `crypto.md5(text)` | 十六进制 MD5 |
| `crypto.aesEcbEncrypt(key, text)` | AES-ECB、PKCS7，返回十六进制。网易云 EAPI 用的是这个参数顺序 |
| `signInPrompt(prompt)` | 弹出提示，不阻塞 |
| `webSignIn({url, cookiesOf, until, userAgent})` | 打开网页，等到 `until` 里的 cookie 都出现，返回 `{cookie}` |
| `openURL` | 只打开 http 和 https |
| `spawn` | 一律拒绝。声匣不启动外部程序，也不带 ffmpeg |
| `waitForRedirect` | 拒绝。iPhone 上不开本机回调端口 |

另外还有 `fetch`、`Headers` 能用到的普通对象、`URLSearchParams`、`TextEncoder`、`TextDecoder`、`atob`、`btoa`、`AbortController`、`setTimeout`、`setInterval`、一个小的 `Buffer`。`Uint8Array` 和 `BigInt` 用引擎自带的。

每次调用大约等 30 秒。一个插件抛错不会关掉另一个插件。超时之后，这只插件的下一次调用仍然可用。

## 不在范围内

- 不把插件脚本打进 ipa
- 不实现 `host.spawn`，因此声明了 ffmpeg 的音质不会播
- 不绕过会员、DRM、地区限制或付费墙。插件自己返回「要登录」或「当前地区不可用」时，原样告诉你
- 不做人声分离

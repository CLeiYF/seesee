# Seesee

[FongMi/TV（影視）](https://github.com/FongMi/TV) 的 iOS / iPadOS 移植版，SwiftUI 实现。兼容 CatVod 配置格式：加载点播与直播配置，聚合浏览、搜索、解析与播放。

> 仅供个人学习与自用侧载。App 本身不提供任何内容，所有数据来自用户自行导入的配置。

## 功能

### 配置
- 从 URL 或本地文件导入；支持明文、base64（`xxxxxxxx**` 标记）、AES（`2423` 开头）三种格式
- 相对路径（`./`、`../`）自动补全；多仓库（`urls`）可切换；配置历史；网络失败回退到上次缓存
- 读取 `sites`、`lives`、`parses`、`flags`、`rules`、`ads`、`headers`、`notice`

### 点播
| 站点类型 | 说明 | 支持 |
|---|---|---|
| type 0 | 苹果 CMS XML | ✅ |
| type 1 / 2 | 苹果 CMS JSON（含筛选） | ✅ |
| type 4 | 自定义接口（ext 可为 URL） | ✅ |
| type 3 `.js` | JS 爬虫（JavaScriptCore） | ✅ |
| type 3 `csp_` / `.py` | Java jar / Python 爬虫 | ❌ iOS 无法运行 |

- 首页推荐与分类、筛选、无限滚动；rect / oval / list 卡片样式与比例
- 详情页：线路、选集、倒序、收藏、继续观看
- 多站并发搜索（最多 5 个同时请求），结果按站点分组；搜索历史；关键词繁转简；可按站点关闭搜索

### 解析与嗅探
- parse type 0（网页嗅探）、1（JSON 解析）、4（超级解析：JSON 与网页嗅探并发，取最先成功）
- 支持 `flags` 和 playUrl 的 `json:` / `parse:` 前缀
- 网页嗅探用隐藏的 WKWebView 加载页面，注入脚本记录 fetch / XHR / `src` 赋值 / DOM 节点 / 资源加载记录；支持嵌套播放页、`rules`（hosts / regex / exclude / script）与 `ads` 拦截

### 播放
- [KSPlayer](https://github.com/kingslay/KSPlayer)：先用 AVPlayer，失败自动切 FFmpeg 内核（FLV / MKV / RTMP 等）
- 倍速、换线路、下一集、超时自动换线（站点 `changeable=0` 时不换）
- 外挂字幕（结果里的 `subs`）与内嵌字幕
- 弹幕：B 站 XML / TXT，滚动、顶部、底部三类，可开关、切换弹幕源
- 跳过片头片尾（按影片记忆）、定时关闭、进度记忆与续播
- 后台音频（Info.plist 已开 `audio` 后台模式，音频会话由 KSPlayer 设置）；画中画和 AirPlay 依赖 KSPlayer 自带能力，App 内暂无专门入口

### 直播
- m3u（`tvg-*`、`group-title`、`catchup`、`#EXTVLCOPT` / `#EXTHTTP` / `#KODIPROP`、`|Header=`）、txt（`#genre#`、`#` 分隔多线路）、JSON 分组
- `名称_密码` 加密分组，解锁后可见；频道自动编号；继承直播源的 ua / referer / origin / header
- EPG：按频道 JSON 接口（`{name}` / `{id}` / `{date}`）与 xmltv（含 `.gz`）
- 回看：`append` / `default` 两种写法与时间占位符，点已播完的节目即可回看
- 多直播源切换，`boot` 指定默认

### 其他
- **本地代理服务**：App 内监听 `127.0.0.1:9978`，提供 `/proxy`（JS 爬虫的 `getProxy` / `js2Proxy` / `proxy://`）与 `/cache`
- **投屏**：DLNA（SSDP 发现 + AVTransport），也能推送给局域网里的 FongMi 影视设备
- **我的**：观看记录、收藏、搜索站点开关、备份导出 / 导入（JSON 文件）

### 未实现
- jar / py 爬虫、闭源 `.so` 插件（迅雷、TVBus 等）：iOS 平台限制
- parse type 2 / 3：依赖 jar
- DRM（ClearKey / Widevine）、YouTube 解析
- DLNA 接收端与设备互推的接收：需要把服务暴露到局域网，且 iOS 后台无法常驻
- `hosts` 改写与 DoH
- 直播源 `api` 指向 JS 爬虫（`liveContent`）

## 环境要求

- macOS + Xcode 26（含 iOS 17+ SDK 与模拟器运行时）
- Metal Toolchain：`xcodebuild -downloadComponent MetalToolchain`（编译 KSPlayer 需要）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`
- 最低系统：iOS / iPadOS 17.0

## 构建与运行

```bash
# 生成 Xcode 工程（.xcodeproj 不入库）
xcodegen generate

# 拉取 SPM 依赖（KSPlayer + FFmpegKit，约 3.9GB）
xcodebuild -resolvePackageDependencies -project Seesee.xcodeproj -scheme Seesee

# 打开工程，选模拟器或真机运行
open Seesee.xcodeproj
```

依赖版本锁定在仓库根目录的 `Package.resolved`（KSPlayer 2.3.4、FFmpegKit 6.1.4）。

**网络受限时**：FFmpegKit 仓库很大，直连 GitHub 可能卡住。可以只对拉依赖这一步让 git 走代理，不改全局配置：

```bash
GIT_CONFIG_COUNT=2 \
GIT_CONFIG_KEY_0=http.proxy GIT_CONFIG_VALUE_0=http://127.0.0.1:7890 \
GIT_CONFIG_KEY_1=http.version GIT_CONFIG_VALUE_1=HTTP/1.1 \
xcodebuild -resolvePackageDependencies -project Seesee.xcodeproj -scheme Seesee
```

### 真机侧载

- 在 `project.yml` 填入 `DEVELOPMENT_TEAM`，或在 Xcode 中选择签名团队
- DLNA 设备发现需要 `com.apple.developer.networking.multicast` 能力：开发者账号里要开通，用侧载工具重签时要保留这个 entitlement
- 首次投屏时系统会请求本地网络权限

## 测试

```bash
xcodebuild test -project Seesee.xcodeproj -scheme Seesee \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

XCTest 共 70 个用例，覆盖 Core 的纯逻辑：配置解码与相对路径、CMS XML / JSON 解析与请求参数、JS 运行时（模块改写、`req`、加解密、cheerio、两种爬虫写法）、解析与嗅探规则、直播源 / EPG / 回看、弹幕解析与轨道分配、本地服务、DLNA 报文、观看记录与备份。UI 靠手动或模拟器点击测试。

### 调试启动参数（仅 DEBUG）

在 Xcode Scheme 的 Arguments 里添加，或用 `xcrun simctl launch` 传入：

| 参数 | 作用 |
|---|---|
| `-config <url>` | 启动时直接加载这个配置地址 |
| `-tab <序号>` | 初始 tab：0 首页、1 直播、2 搜索、3 我的 |
| `-play <siteKey>/<vodId>/<线路序号>` | 加载完成后直接打开该影片并播放 |

```bash
xcrun simctl launch booted com.cleiyf.seesee -config http://127.0.0.1:8765/config.json -tab 1
```

## 项目结构

```
project.yml              XcodeGen 工程描述（依赖、Info.plist、entitlements）
Package.resolved         SPM 依赖版本锁定
Seesee/
├── App/                 入口、AppState（当前配置 / 站点）
├── Core/                不依赖 UIKit 的业务逻辑
│   ├── Config/          配置解码（ConfigDecoder）、VodConfig、多仓库加载
│   ├── Model/           Site、Vod、VodResult、Flag 等（字段与 CMS JSON 一致）
│   ├── Source/          SiteAPI 协议：CMSSource（0/1/2）、CustomSource（4）、搜索、Sniffer 规则
│   ├── JS/              JavaScriptCore 运行时：ES module 改写、全局函数、加解密、JSSpider
│   ├── Parse/           ParseJob（解析调度）、片头片尾、弹幕解析
│   ├── Live/            直播源解析、EPG、回看、直播加载
│   └── Net/             HTTP、本地服务（9978）、DLNA、设备互推
├── Player/              PlayerEngine（KSPlayer 封装）、WebSniffer（WKWebView 嗅探）
├── Store/               Library：配置历史、观看记录、收藏、备份（单个 JSON 文件）
├── UI/                  SwiftUI 页面：首页、分类、详情、搜索、直播、播放器、弹幕、投屏、我的、配置
└── Resources/js/lib/    cat.js、cheerio、crypto-js 等（来自原项目 quickjs 模块）
SeeseeTests/             XCTest
```

**几处关键实现**
- **JS 爬虫**：JavaScriptCore 不对外开放 ES module，所以用正则把 `import` / `export` 改写成函数包装。每个站点一个 JSContext，跑在专用线程上，同步 `req` 会阻塞该线程，与原项目行为一致。不支持循环依赖、top-level await 和 live binding。
- **网页嗅探**：Core 层通过闭包注入嗅探能力，不依赖 WebKit；UI 层用 WKWebView 实现。
- **数据存储**：观看记录、收藏等存在一个 JSON 文件里，备份直接导出这个文件。记录上万条时再换数据库。

## 许可证

本项目以 **GPL-3.0** 发布：原项目 FongMi/TV 采用 GPL-3.0，依赖的 KSPlayer 与 FFmpegKit 也是 GPL-3.0。分发本项目或其衍生作品时，必须按 GPL-3.0 提供完整源码。

## 致谢

- [FongMi/TV](https://github.com/FongMi/TV)：原项目，配置格式与业务逻辑来源
- [CatVod](https://github.com/CatVodTVOfficial/CatVodTVJarLoader)：配置与爬虫接口规范
- [KSPlayer](https://github.com/kingslay/KSPlayer) / [FFmpegKit](https://github.com/kingslay/FFmpegKit)：播放内核
- [cheerio](https://github.com/cheeriojs/cheerio)、[crypto-js](https://github.com/brix/crypto-js)：JS 爬虫内置库

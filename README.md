# Seesee

[FongMi/TV（影視）](https://github.com/FongMi/TV) 的 iOS / iPadOS 移植版，SwiftUI 实现。兼容 CatVod 配置格式：加载点播与直播配置，聚合浏览、搜索、解析与播放。

> 仅供个人学习与自用侧载。App 本身不提供任何内容，所有数据来自用户自行导入的配置。

## 功能

### 配置
- 从 URL 或本地文件导入；支持明文、base64（`xxxxxxxx**` 标记）、AES（`2423` 开头）三种格式；按 OkHttp UA 拉取（部分配置服务器按 UA 分流）
- 相对路径（`./`、`../`）自动补全；多仓库（`urls`）可切换；配置历史；网络失败回退到上次缓存
- 读取 `sites`、`lives`、`parses`、`flags`、`rules`、`ads`、`headers`、`proxy`、`hosts`、`notice`

### 点播
| 站点类型 | 说明 | 支持 |
|---|---|---|
| 0 / 1 / 2 | 苹果 CMS XML / JSON | ✅ |
| 3 + `.js` | JS 爬虫（JavaScriptCore），兼容 cat 与 `export default` 两种写法 | ✅ |
| 3 + `csp_Xxx` | jar 爬虫：内置 JS 重写版（见下），或从外接 JS 仓库加载 `Xxx.js` | 部分 |
| 4 | 自定义 HTTP 接口（如 drpy-node T4） | ✅ |
| 3 + `.py` | Python 爬虫 | ❌ |

- 内置 JS 版 jar 爬虫（`Seesee/Resources/js/spider/`）：Douban、Jianpian、Dm84、Ysj、Zxzj、FirstAid、Kanqiu、XPath / XPathFilter / XPathMac / XPathMacFilter、AppYsV2、AList、WebDAV、Quark、UC、TianYi、Pan123、Ali、YiDongYun、TgSearch*（盘搜）、DianYingYunJi、KuaKeS、Xb6v
- 网盘（夸克、UC、天翼、123、阿里、移动、百度）凭证与安卓一致，取自站点 `ext`（`cookie`、`uccookie`、`tianyicookie`、`token` 等）
- 首页分类、筛选、分页；文件夹浏览（`vod_tag=folder`）；`msearch:` 推荐项跳转搜索
- 聚合搜索（并发、可按站点筛选、滚动翻页）；详情页换源（快搜同名）、刷新、点演员导演搜索
- 海报支持 `url@Referer=…@User-Agent=…` 请求头写法

### 解析与嗅探
- parse 0（嗅探）、1（JSON）、4（多个解析并发取最快）；播放中可切换解析接口
- `flags`、`rules`、`ads` 过滤

### 播放
- KSPlayer：AVPlayer 优先，失败自动切 FFmpeg；超时或失败自动换线（可关闭）
- 手势：单击显隐、双击暂停、横向拖动快进、左半屏竖拖亮度、长按 2 倍速；锁定、旋转
- 倍速（可设默认）、画面比例、音轨、字幕（结果内 subs）、画中画、选集面板、上一集 / 下一集、单集循环、片头片尾跳过、续播
- 弹幕：B 站 XML / TXT，滚动、顶部、底部；可开关、切换源；可接外部弹幕 API（兼容 FongMi 自定义接口，如 danmu_api）
- DLNA 投屏、推送到 FongMi 设备

### 直播
- m3u / txt / json 源，`api` 可为 JS 爬虫（`live()`）
- EPG 节目单、回看、密码分组
- 全屏与控制栏、频道收藏、上下切台、手动换线、记住上次频道；切换 tab 时暂停

### 其他
- 观看记录、收藏、JSON 备份与恢复、无痕模式、清除缓存
- 本地服务（`/proxy`、`/cache`）供 JS 爬虫本地代理

### 未实现
- Python 爬虫、parse type 2 / 3（依赖 jar）
- 未移植成 JS 的 jar 爬虫（站点已失效的、成人站点、本机功能类）
- 迅雷 / 磁力 / ed2k、TVBus、Force 等 P2P 协议，Widevine DRM
- DoH；`hosts` 只改写 URL，HTTPS 下仍按新域名校验证书
- 接收投屏、被推送、设备间同步（iOS 后台不能常驻服务）
- 热搜与联想词、外挂本地字幕、下载、壁纸主题

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

XCTest 共 84 个用例，覆盖 Core 的纯逻辑：配置解码与相对路径、CMS XML / JSON 解析与请求参数、JS 运行时（模块改写、`req`、加解密、cheerio、两种爬虫写法、内置爬虫）、解析与嗅探规则、proxy / hosts、直播源 / EPG / 回看、弹幕解析与外接弹幕 API、本地服务、DLNA 报文、观看记录与备份。UI 靠手动或模拟器点击测试。

联网检查（依赖第三方站点，结果随站点状态变化）：

```bash
# 内置 JS 爬虫冒烟（Node + curl 模拟 req）
NO_PROXY_ALL=1 node scripts/spider-smoke.mjs            # 全部
NO_PROXY_ALL=1 node scripts/spider-smoke.mjs Jianpian   # 单个

# 在真实 JavaScriptCore 里跑网盘爬虫
TEST_RUNNER_SEESEE_LIVE=1 xcodebuild test -project Seesee.xcodeproj -scheme Seesee \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SeeseeTests/LiveSpiderTests
```

### 调试启动参数（仅 DEBUG）

在 Xcode Scheme 的 Arguments 里添加，或用 `xcrun simctl launch` 传入：

| 参数 | 作用 |
|---|---|
| `-config <url>` | 启动时直接加载这个配置地址 |
| `-tab <序号>` | 初始 tab：0 首页、1 直播、2 搜索、3 我的 |
| `-play <siteKey>/<vodId>/<线路序号>` | 加载完成后直接打开该影片并播放 |
| `-search <关键词>` | 加载完成后直接搜索 |
| `-folder <siteKey>/<id>` | 加载完成后直接打开文件夹 |

`vodId` 含 `/` 时用 `%2F` 编码。

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

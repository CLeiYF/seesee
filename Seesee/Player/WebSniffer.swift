import Foundation
import WebKit

/// 网页嗅探（对应 CustomWebView）：隐藏 WKWebView 加载页面，抓取页面里发出的视频地址。
/// WKWebView 拿不到子资源请求，所以注入脚本 hook fetch / XHR / src 赋值 / DOM 变化 / Resource Timing，把 URL 回传给原生判断。
/// ponytail: 跨域 iframe 里的 Resource Timing 只在该 frame 内可见（脚本已注入所有 frame）；Service Worker 内发出的请求抓不到
@MainActor
final class WebSniffer: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<ParseJob.Output, Error>?
    private var timer: Task<Void, Never>?
    private var pageURL = ""
    private var headers: [String: String] = [:]
    private var click = ""
    /// 子页面嗅探（player/?url= 链接）
    private var children: [WebSniffer] = []
    private var seen = Set<String>()
    private let detect: Bool

    static let timeout: TimeInterval = 15
    private static let player = #/player/.*[?&][^=&]+=https?://#

    private init(detect: Bool) { self.detect = detect }

    /// 供 ParseJob 注入
    static let sniff: ParseJob.Sniff = { url, headers, click in
        try await WebSniffer.run(url, headers: headers, click: click)
    }

    static func run(_ url: String, headers: [String: String], click: String, detect: Bool = true) async throws -> ParseJob.Output {
        let s = WebSniffer(detect: detect)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                s.start(url, headers: headers, click: click, continuation: cont)
            }
        } onCancel: {
            Task { @MainActor in s.finish(.failure(CancellationError())) }
        }
    }

    private func start(_ url: String, headers: [String: String], click: String, continuation: CheckedContinuation<ParseJob.Output, Error>) {
        guard let u = URL(string: url) else { return continuation.resume(throwing: ParseJob.Failure.failed) }
        self.continuation = continuation
        pageURL = url
        self.headers = headers
        self.click = click
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsInlineMediaPlayback = true
        config.userContentController.add(WeakHandler(self), name: "sniff")
        config.userContentController.addUserScript(WKUserScript(source: Self.hook, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 667), configuration: config)
        wv.navigationDelegate = self
        if let ua = headers.first(where: { $0.key.lowercased() == "user-agent" })?.value { wv.customUserAgent = ua } else { wv.customUserAgent = HTTP.chrome }
        // WKWebView 必须在窗口层级里才会跑 JS 计时器；放到屏幕外
        if let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first {
            wv.frame.origin = CGPoint(x: -10000, y: 0)
            window.addSubview(wv)
        }
        webView = wv
        var req = URLRequest(url: u)
        for (k, v) in headers where k.lowercased() != "user-agent" { req.setValue(v, forHTTPHeaderField: k) }
        wv.load(req)
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.timeout))
            self?.finish(.failure(ParseJob.Failure.failed))
        }
    }

    private func finish(_ result: Swift.Result<ParseJob.Output, Error>) {
        guard let c = continuation else { return }
        continuation = nil
        timer?.cancel()
        children.forEach { $0.finish(.failure(CancellationError())) }
        children = []
        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "sniff")
        webView?.removeFromSuperview()
        webView = nil
        c.resume(with: result)
    }

    // MARK: - JS → 原生

    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let raw = message.body as? String else { return }
        check(raw)
    }

    private func check(_ raw: String) {
        guard continuation != nil, let url = URL(string: raw, relativeTo: URL(string: pageURL))?.absoluteString else { return }
        guard let host = URLComponents(string: url)?.host, !host.isEmpty, !Sniffer.isAd(host) else { return }
        // 二级播放页：另开一个嗅探器（对应 CustomWebView.onParseAdd）
        if detect, url.contains(Self.player), seen.insert(url).inserted, seen.count <= 5 {
            let child = WebSniffer(detect: false)
            children.append(child)
            Task { [weak self] in
                if let out = try? await withCheckedThrowingContinuation({ c in child.start(url, headers: self?.headers ?? [:], click: "", continuation: c) }) {
                    self?.finish(.success(out))
                }
            }
            return
        }
        if !detect, url == pageURL { return }
        guard Sniffer.isVideoFormat(url) else { return }
        var h = headers
        h["Referer"] = h["Referer"] ?? pageURL
        finish(.success(ParseJob.Output(url: url, headers: h, from: "")))
    }

    // MARK: - 导航

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // 页面加载完执行 click 与 rules 里的脚本（对应 CustomWebView.evaluate）
        var scripts = Sniffer.scripts(for: pageURL)
        if !click.isEmpty, !scripts.contains(click) { scripts.insert(click, at: 0) }
        for js in scripts where !js.isEmpty { webView.evaluateJavaScript(js) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        // 主框架/子框架跳转到的地址本身可能就是视频
        if let u = action.request.url?.absoluteString { check(u) }
        if let host = action.request.url?.host, Sniffer.isAd(host) { return .cancel }
        return .allow
    }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        // 与原项目 onReceivedSslError → proceed 一致
        guard let trust = challenge.protectionSpace.serverTrust else { return (.performDefaultHandling, nil) }
        return (.useCredential, URLCredential(trust: trust))
    }

    /// 页面内 hook：fetch / XHR / video|source|iframe 的 src / 性能条目（PerformanceObserver 能看到大多数资源请求）
    private static let hook = """
    (function(){
      const post = u => { try { if (u) window.webkit.messageHandlers.sniff.postMessage(String(u)) } catch(e){} };
      const of = window.fetch; if (of) window.fetch = function(i, o){ post(typeof i === 'string' ? i : (i && i.url)); return of.apply(this, arguments) };
      const oo = XMLHttpRequest.prototype.open; XMLHttpRequest.prototype.open = function(m, u){ post(u); return oo.apply(this, arguments) };
      const watch = el => { if (el && el.src) post(el.src); if (el && el.currentSrc) post(el.currentSrc) };
      ['HTMLMediaElement','HTMLSourceElement','HTMLIFrameElement'].forEach(n => {
        const p = window[n] && window[n].prototype, d = p && Object.getOwnPropertyDescriptor(p, 'src');
        if (d && d.set) Object.defineProperty(p, 'src', { get: d.get, set: function(v){ post(v); d.set.call(this, v) }, configurable: true });
      });
      try { new PerformanceObserver(l => l.getEntries().forEach(e => post(e.name))).observe({ entryTypes: ['resource'] }) } catch(e){}
      new MutationObserver(ms => ms.forEach(m => m.addedNodes.forEach(n => {
        if (n.tagName && /^(VIDEO|SOURCE|IFRAME)$/.test(n.tagName)) watch(n);
        if (n.querySelectorAll) n.querySelectorAll('video,source,iframe').forEach(watch);
      }))).observe(document.documentElement || document, { childList: true, subtree: true });
    })();
    """
}

/// WKUserContentController 强引用 handler，用弱引用打破循环
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(uc, didReceive: message)
    }
}

import Foundation

/// 用户设置（对应原项目 Setting.java 中 iOS 适用的几项），存 UserDefaults
enum Prefs {
    private static let d = UserDefaults.standard

    /// 默认倍速
    static var rate: Float {
        get { d.object(forKey: "pref.rate") as? Float ?? 1 }
        set { d.set(newValue, forKey: "pref.rate") }
    }

    /// 超时 / 失败自动换线
    static var autoSwitch: Bool {
        get { d.object(forKey: "pref.autoSwitch") as? Bool ?? true }
        set { d.set(newValue, forKey: "pref.autoSwitch") }
    }

    /// 无痕：不写观看记录
    static var incognito: Bool {
        get { d.bool(forKey: "pref.incognito") }
        set { d.set(newValue, forKey: "pref.incognito") }
    }

    /// Emby 类站点总开关：关闭后首页站点列表和搜索里都不出现
    static var emby: Bool {
        get { d.object(forKey: "pref.emby") as? Bool ?? true }
        set { d.set(newValue, forKey: "pref.emby") }
    }

    /// 清缓存：URLCache + JS 爬虫上下文（下次使用重新加载脚本）
    static func clearCache() {
        URLCache.shared.removeAllCachedResponses()
        JSSpider.reset()
    }
}

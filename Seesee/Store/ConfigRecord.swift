import Foundation
import SwiftData

/// 配置历史：保存最近一次成功解码的文本，加载失败时回退
@Model
final class ConfigRecord {
    @Attribute(.unique) var url: String
    var name: String
    var text: String
    var home: String
    var time: Date

    init(url: String, name: String = "", text: String = "", home: String = "", time: Date = .now) {
        self.url = url
        self.name = name
        self.text = text
        self.home = home
        self.time = time
    }
}

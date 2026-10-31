import Foundation

/// 对应 utils/Sniffer.isVideoFormat（rules 在 M4 接入）
enum Sniffer {
    static func isVideoFormat(_ url: String) -> Bool {
        if url.contains("url=http") || url.contains("v=http") || url.contains(".html") { return false }
        let sniffer = #/https?://[^\s]{12,}\.(?:m3u8|mp4|mkv|flv|mp3|m4a|aac|mpd)(?:\?.*)?|https?://.*?video/tos[^\s]*|rtmp:[^\s]+/#
        return url.contains(sniffer)
    }
}

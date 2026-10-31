import Foundation

/// type 0 苹果 CMS XML：<rss><class><ty id>…</ty></class><list pagecount><video>…<dl><dd flag>…</dd></dl></video></list></rss>
final class XMLResult: NSObject, XMLParserDelegate {
    private var result = VodResult()
    private var vod: Vod?
    private var text = ""
    private var attrs: [String: String] = [:]

    static func parse(_ xml: String) -> VodResult {
        let p = XMLResult()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = p
        parser.parse()
        return p.result
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        attrs = attributes
        switch name {
        case "video": vod = Vod()
        case "list": result.pagecount = attributes["pagecount"].flatMap { Int($0) }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, foundCDATA block: Data) { text += HTTP.string(block) }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { text = "" }
        if name == "ty" {
            result.classes.append(VodClass(typeId: attrs["id"] ?? "", typeName: t))
            return
        }
        guard vod != nil else { return }
        switch name {
        case "id": vod?.vodId = t
        case "name": vod?.vodName = t
        case "type": vod?.typeName = t
        case "pic": vod?.vodPic = t
        case "note": vod?.vodRemarks = t
        case "year": vod?.vodYear = t
        case "area": vod?.vodArea = t
        case "director": vod?.vodDirector = t
        case "actor": vod?.vodActor = t
        case "des": vod?.vodContent = t
        case "dd": vod?.xmlFlags.append(Flag(flag: attrs["flag"] ?? "", urls: t))
        case "video":
            if let v = vod { result.list.append(v) }
            vod = nil
        default: break
        }
    }
}

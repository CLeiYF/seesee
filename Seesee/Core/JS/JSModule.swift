import Foundation

/// JavaScriptCore 不对外开放 ES module，这里把 import/export 改写成函数包装：
/// `(function(__exports){ …; return __exports })`，import 变成 `__import("<已解析的地址>")`。
/// ponytail: 基于正则改写，覆盖 drpy/T3/cat 常见写法；不支持循环依赖、top-level await、live binding
enum JSModule {
    static func transform(_ code: String, resolve: (String) -> String) -> String {
        var exports: [String] = []
        var n = 0
        func temp() -> String { n += 1; return "__m\(n)" }
        func quoted(_ s: String) -> String {
            let d = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
            return String(HTTP.string(d).dropFirst().dropLast())
        }
        func load(_ spec: Substring) -> String { "__import(\(quoted(resolve(String(spec)))))" }
        let lead = #"(^|[;}\n])([ \t]*)"#

        var s = code
        // export { a as b, c } [from 'x'];
        s = s.replacing(try! Regex(lead + #"export\s*\{([^}]*)\}(?:\s*from\s*(["'])([^"']+)\4)?[ \t]*;?"#)) { m in
            let src = m.output[5].substring.map { load($0) }
            for item in (m.output[3].substring ?? "").split(separator: ",") {
                let parts = item.split(separator: " ", omittingEmptySubsequences: true)
                guard let local = parts.first else { continue }
                let name = parts.count == 3 && parts[1] == "as" ? parts[2] : local
                exports.append("__exports[\(quoted(String(name)))] = \(src.map { "\($0)[\(quoted(String(local)))]" } ?? String(local));")
            }
            return "\(m.output[1].substring ?? "")\(m.output[2].substring ?? "");"
        }
        // export * from 'x';
        s = s.replacing(try! Regex(lead + #"export\s*\*\s*from\s*(["'])([^"']+)\3[ \t]*;?"#)) { m in
            exports.append("Object.assign(__exports, \(load(m.output[4].substring ?? "")));")
            return "\(m.output[1].substring ?? "")\(m.output[2].substring ?? "");"
        }
        // export default …
        s = s.replacing(try! Regex(lead + #"export\s+default\s+"#)) { m in
            "\(m.output[1].substring ?? "")\(m.output[2].substring ?? "")__exports.default = "
        }
        // export function/class/const/let/var name
        s = s.replacing(try! Regex(lead + #"export\s+((?:async\s+)?function\s*\*?|class|const|let|var)\s+([\w$]+)"#)) { m in
            let name = String(m.output[4].substring ?? "")
            exports.append("__exports[\(quoted(name))] = \(name);")
            return "\(m.output[1].substring ?? "")\(m.output[2].substring ?? "")\(m.output[3].substring ?? "") \(name)"
        }
        // import … from 'x' / import 'x'
        s = s.replacing(try! Regex(lead + #"import\s*(?:([^'";()=]+?)\s*from\s*)?(["'])([^"']+)\4[ \t]*;?"#)) { m in
            let prefix = "\(m.output[1].substring ?? "")\(m.output[2].substring ?? "")"
            let call = load(m.output[5].substring ?? "")
            guard let clause = m.output[3].substring?.trimmingCharacters(in: .whitespacesAndNewlines), !clause.isEmpty else {
                return prefix + call + ";"
            }
            let t = temp()
            var out = "var \(t) = \(call);"
            var rest = Substring(clause)
            // 默认导入在最前：`X` 或 `X, {…}` / `X, * as ns`
            if let first = rest.first, first != "{", first != "*" {
                let end = rest.firstIndex(of: ",") ?? rest.endIndex
                out += " var \(rest[..<end].trimmingCharacters(in: .whitespaces)) = \(t).default;"
                rest = end < rest.endIndex ? rest[rest.index(after: end)...] : ""
            }
            let r = rest.trimmingCharacters(in: .whitespacesAndNewlines)
            if r.hasPrefix("*") {
                out += " var \(r.split(separator: " ").last ?? "") = \(t);"
            } else if r.hasPrefix("{") {
                let body = r.dropFirst().dropLast().replacing(#/\s+as\s+/#, with: ": ")
                out += " var {\(body)} = \(t);"
            }
            return prefix + out
        }
        return "(function(__exports){\n\(s)\n;\(exports.joined(separator: "\n"))\nreturn __exports;\n})"
    }
}

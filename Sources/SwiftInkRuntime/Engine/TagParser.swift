enum TagParser {
    static func parse(_ raw: String) -> (key: String, value: String?) {
        guard let colonIndex = raw.firstIndex(of: ":") else {
            return (key: raw, value: nil)
        }
        let key = raw[raw.startIndex..<colonIndex]
            .filter { !$0.isWhitespace }
        let afterColon = raw[raw.index(after: colonIndex)...]
        let value = afterColon.drop(while: { $0.isWhitespace })
            .reversed()
            .drop(while: { $0.isWhitespace })
            .reversed()
        return (key: String(key), value: String(value))
    }
}

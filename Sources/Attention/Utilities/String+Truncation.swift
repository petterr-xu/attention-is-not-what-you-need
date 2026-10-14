import Foundation

extension String {
    /// 按**字符**（grapheme cluster）截断，超长时补省略号。
    ///
    /// 不能用 `utf8.count` / `utf16.count` 来判断长度和切片：一个汉字是 3 字节、2 个
    /// UTF-16 单元，按字节数截出来的长度和视觉完全对不上，还会把 emoji 拦腰切断。
    /// `Character` 才是「用户眼里一个字」的粒度。
    func truncated(to limit: Int, ellipsis: String = "…") -> String {
        guard limit > 0 else { return "" }
        return count <= limit ? self : String(prefix(limit)) + ellipsis
    }
}

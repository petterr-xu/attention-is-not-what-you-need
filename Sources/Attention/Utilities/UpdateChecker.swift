import Foundation
import Combine

/// 检查 GitHub Releases 上是否有新版本。
///
/// 只负责「发现」新版本，不做下载与替换：应用未经 Apple 公证，
/// 浏览器下载的新包会重新带上 quarantine 标记，自动替换仍会被 Gatekeeper 拦下，
/// 省不掉用户手动这一步，反而多引入一套密钥与 appcast 的维护成本。
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    /// 有新版本时的版本号（如 "1.0.1"）；已是最新时为 nil，界面据此决定是否显示提示
    @Published private(set) var availableVersion: String?
    /// 新版本对应的 Release 页面
    @Published private(set) var releaseURL: URL?

    private static let feedURL = URL(
        string: "https://api.github.com/repos/petterr-xu/attention-is-not-what-you-need/releases/latest"
    )!
    /// 复查间隔：应用是常驻的菜单栏程序，开机后可能连开数天
    private static let checkInterval: Duration = .seconds(6 * 3600)

    private var monitorTask: Task<Void, Never>?

    private init() {}

    /// 启动后延迟做首次检查，之后定期复查
    func start() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            // 避开启动瞬间，不与窗口初始化抢资源
            try? await Task.sleep(for: .seconds(5))
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: Self.checkInterval)
            }
        }
    }

    /// 手动触发一次检查（供菜单里的「检查更新」使用）。
    /// 返回发现的新版本号；已是最新或检查失败都返回 nil——对用户而言没有区别。
    func checkManually() async -> String? {
        await check()
        return availableVersion
    }

    /// 查询最新 Release 并与本地版本比对。
    /// 网络错误、超时、限流、尚未发布过 Release、解析失败——一律静默忽略，不打扰用户。
    private func check() async {
        guard let local = Self.localVersion else { return }

        var request = URLRequest(url: Self.feedURL)
        // GitHub API 强制要求 User-Agent，缺失会直接返回 403
        request.setValue("Attention", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let release = try? JSONDecoder().decode(Release.self, from: data)
        else { return }

        let remote = release.tagName.hasPrefix("v")
            ? String(release.tagName.dropFirst())
            : release.tagName

        guard Self.isNewer(remote, than: local) else {
            // 已是最新（本地版本甚至更高，比如开发中构建）：清掉可能残留的提示
            availableVersion = nil
            releaseURL = nil
            return
        }

        availableVersion = remote
        releaseURL = release.htmlURL
    }

    // MARK: - 辅助

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    /// 本地应用版本，对应 Info.plist 的 CFBundleShortVersionString
    private static var localVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// 按数值逐段比较版本号。
    /// 不能用字符串比较："1.0.10" 字典序小于 "1.0.9"，但版本号上更大。
    private static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(lhs.count, rhs.count) {
            // 位数不足的一段按 0 处理，使 "1.0" 与 "1.0.0" 等价
            let a = index < lhs.count ? lhs[index] : 0
            let b = index < rhs.count ? rhs[index] : 0
            if a != b { return a > b }
        }
        return false
    }
}

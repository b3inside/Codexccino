import Foundation

enum AppIdentity {
    static let name = "Codexccino"
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.8"
    }
}

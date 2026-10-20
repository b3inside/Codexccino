import Foundation

enum AppIdentity {
    static let name = "Codpresso"
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.9"
    }
}

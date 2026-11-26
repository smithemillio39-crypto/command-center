import Foundation
import SwiftUI
import UIKit

/// One release listed in the update feed the PC publishes after every build.
struct UpdateRelease: Decodable, Identifiable {
    let version: String
    let buildVersion: String
    let date: String?
    let localizedDescription: String?
    let downloadURL: String
    let size: Int64?

    var id: String { buildVersion }
}

private struct FeedApp: Decodable {
    let bundleIdentifier: String
    let versions: [UpdateRelease]
}

private struct Feed: Decodable {
    let apps: [FeedApp]
}

enum UpdateError: Error {
    case badResponse
    case notListed
}

/// Reads the same SideStore/AltStore source the PC writes after each build, so
/// the phone learns a new build exists without hunting for an artifact.
@MainActor
final class Updater: ObservableObject {
    static let sourceURL = URL(string:
        "https://raw.githubusercontent.com/smithemillio39-crypto/command-center/main/updates/source.json")!
    static let bundleID = "com.personal.commandcenter"

    @Published private(set) var latest: UpdateRelease?
    @Published private(set) var lastChecked: Date?
    @Published private(set) var checking = false
    @Published private(set) var status: String?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var displayVersion: String { "\(currentVersion) (\(currentBuild))" }

    var isUpdateAvailable: Bool {
        guard let latest, let remote = Int(latest.buildVersion) else { return false }
        return remote > (Int(currentBuild) ?? 0)
    }

    func check() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }

        do {
            var request = URLRequest(url: Self.sourceURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 12
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw UpdateError.badResponse
            }
            let feed = try JSONDecoder().decode(Feed.self, from: data)
            guard let app = feed.apps.first(where: { $0.bundleIdentifier == Self.bundleID }) else {
                throw UpdateError.notListed
            }
            latest = app.versions
                .sorted { (Int($0.buildVersion) ?? 0) > (Int($1.buildVersion) ?? 0) }
                .first
            lastChecked = Date()
            if isUpdateAvailable {
                status = "Build \(latest?.buildVersion ?? "?") is ready to install."
            } else {
                status = "Up to date."
            }
        } catch {
            status = "Could not reach the update feed."
        }
    }

    /// Hands the IPA to SideStore or AltStore when one is installed; otherwise
    /// opens the download so it can be sideloaded the usual way.
    func install() {
        guard let latest, let download = URL(string: latest.downloadURL) else { return }
        let encoded = download.absoluteString
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? download.absoluteString
        for scheme in ["sidestore", "altstore"] {
            if let link = URL(string: "\(scheme)://install?url=\(encoded)"),
               UIApplication.shared.canOpenURL(link) {
                UIApplication.shared.open(link)
                return
            }
        }
        UIApplication.shared.open(download)
    }
}

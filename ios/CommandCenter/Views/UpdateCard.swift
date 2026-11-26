import SwiftUI

/// The bar that appears when the PC has published a build newer than this one.
struct UpdateCard: View {
    @ObservedObject var updater: Updater

    var body: some View {
        if updater.isUpdateAvailable, let latest = updater.latest {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.ccMint)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Build \(latest.buildVersion) is ready")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(note(for: latest))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Button {
                    Haptics.tap()
                    updater.install()
                } label: {
                    Text("Update")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassSurface(Capsule(), tint: .ccMint, strength: 0.22)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .glassCard(tint: .ccMint, strength: 0.10, radius: 22)
        }
    }

    private func note(for release: UpdateRelease) -> String {
        if let description = release.localizedDescription, !description.isEmpty {
            return description
        }
        if let date = release.date {
            return "Published \(date)"
        }
        return "Tap Update to install it."
    }
}

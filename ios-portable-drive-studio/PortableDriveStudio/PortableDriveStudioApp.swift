import SwiftUI

@main
struct PortableDriveStudioApp: App {
    var body: some Scene {
        WindowGroup {
            StudioView()
                .preferredColorScheme(.dark)
        }
    }
}

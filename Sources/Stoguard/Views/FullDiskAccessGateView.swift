import SwiftUI
import AppKit

/// Single permission surface — nothing scans until Full Disk Access is granted.
/// Pattern from [Purge](https://github.com/jithin-sabu/purge-app) (FullDiskAccessGateView).
struct FullDiskAccessGateView: View {
    @EnvironmentObject var model: AppModel
    @State private var didOpenSettings = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 44, weight: .thin))
                .foregroundStyle(Theme.secondaryText)

            Text("Stoguard needs Full Disk Access")
                .font(.title2.weight(.semibold))

            Text("One permission unlocks every scan. Without it, macOS shows a separate dialog for each protected folder — that's the spam you saw.")
                .font(.callout)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Button {
                didOpenSettings = true
                openSettings()
                model.refreshPermission()
            } label: {
                Text("Open System Settings")
            }
            .buttonStyle(PrimaryPillButtonStyle())

            if didOpenSettings {
                Text("Privacy & Security → Full Disk Access → turn on Stoguard, then return here.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .task { await pollUntilGranted() }
    }

    private func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }

    private func pollUntilGranted() async {
        while !Task.isCancelled {
            model.refreshPermission()
            if model.hasFullDiskAccess { return }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}

import SwiftUI
import AppKit

struct OnboardingSheetView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(GhostButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            ScrollView {
                VStack(spacing: 20) {
                    AppMark(size: 56)
                    Text("Welcome to Stoguard")
                        .font(.title2.weight(.bold))
                    Text(AppInfo.tagline)
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)

                    onboardingStep(
                        icon: "lock.shield",
                        title: "Grant Full Disk Access once",
                        detail: "Stoguard needs this to scan protected Library folders without spamming permission dialogs."
                    )
                    onboardingStep(
                        icon: "magnifyingglass",
                        title: "Scan by category or all at once",
                        detail: "Developer, package managers, Docker, AI tools — each explained in plain English."
                    )
                    onboardingStep(
                        icon: "trash",
                        title: "Everything goes to the Trash",
                        detail: "Nothing is permanently deleted. You confirm before every clean."
                    )
                    onboardingStep(
                        icon: "terminal",
                        title: "Some things need a command",
                        detail: "Docker and Ollama get a copy-paste CLI command instead of a risky delete button."
                    )

                    Button("Open System Settings") {
                        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(SecondaryOutlineButtonStyle())
                }
                .padding(24)
                .frame(maxWidth: 420)
            }
        }
        .frame(width: 460, height: 520)
        .background(Theme.bg)
    }

    private func onboardingStep(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.navy)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.caption).foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .softTintCard(radius: 10)
    }
}

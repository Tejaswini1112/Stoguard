import SwiftUI
import AppKit

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        Group {
            if model.hasFullDiskAccess {
                GeometryReader { geo in
                    NavigationSplitView(columnVisibility: $columnVisibility) {
                        SidebarView()
                            .navigationSplitViewColumnWidth(min: 200, ideal: 228, max: 260)
                    } detail: {
                        SectionDetailView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .navigationSplitViewStyle(.balanced)
                    .onAppear { updateColumns(width: geo.size.width) }
                    .onChange(of: geo.size.width) { _, w in updateColumns(width: w) }
                }
            } else {
                FullDiskAccessGateView()
            }
        }
        .tint(Theme.navy)
        .background(Theme.bg)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermission()
            model.refreshDisk()
        }
        .onAppear {
            model.refreshPermission()
            model.refreshDisk()
            model.refreshTrashSummary()
            model.bootstrapPlatform()
        }
        .alert(item: Binding(
            get: { model.cleanPrompt },
            set: { model.cleanPrompt = $0 }
        )) { prompt in
            Alert(
                title: Text(prompt.alertTitle),
                message: Text(prompt.alertMessage),
                primaryButton: .destructive(Text(prompt.confirmButtonTitle)) {
                    Task { await model.executeCleanPrompt(prompt) }
                },
                secondaryButton: .cancel(Text("Cancel")) {
                    model.cancelCleanPrompt()
                }
            )
        }
        .sheet(isPresented: $model.showOnboarding) {
            OnboardingSheetView()
                .environmentObject(model)
        }
        .alert("Path safety", isPresented: Binding(
            get: { model.pathSafetyNotice != nil },
            set: { if !$0 { model.pathSafetyNotice = nil } }
        )) {
            Button("OK", role: .cancel) { model.pathSafetyNotice = nil }
        } message: {
            Text(model.pathSafetyNotice ?? "")
        }
    }

    private func updateColumns(width: CGFloat) {
        // Narrow: detail only — sidebar via toolbar toggle (no wasted space)
        let target: NavigationSplitViewVisibility = width < 720 ? .detailOnly
            : width < 920 ? .doubleColumn
            : .all
        if columnVisibility != target {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { columnVisibility = target }
        }
    }
}

import SwiftUI

/// The single place a workspace explains missing Accessibility access.
/// While shown it watches for the grant, so the user never has to come back and retry.
struct HostAccessCard: View {
    let appName: String
    var detail: String?
    var actionEnabled = true
    var request: () -> Void
    var refresh: () -> Void

    var body: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 28)).foregroundStyle(.orange)
                    .frame(width: 34).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Allow Bellith to work with \(appName)").font(.headline)
                    Text("Bellith reads your \(appName) project through macOS Accessibility. Turn on Bellith in Privacy & Security → Accessibility. This page continues automatically once access is granted.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        Button("Open Accessibility Settings…", action: request)
                            .buttonStyle(.borderedProminent).disabled(!actionEnabled)
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Waiting for access").font(.callout).foregroundStyle(.secondary)
                        }.accessibilityElement(children: .combine)
                    }.padding(.top, 4)
                }
                Spacer(minLength: 0)
            }.padding(10)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                refresh()
            }
        }
    }
}

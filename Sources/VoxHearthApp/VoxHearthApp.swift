import SwiftUI
import VoxHearthCore

@main
struct VoxHearthApp: App {
    var body: some Scene {
        MenuBarExtra(AppIdentity.name, systemImage: "waveform") {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppIdentity.name)
                    .font(.headline)
                Text(AppIdentity.tagline)
                    .foregroundStyle(.secondary)
                Divider()
                SettingsLink {
                    Label("Settings", systemImage: "gear")
                }
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding()
            .frame(width: 280)
        }
        .menuBarExtraStyle(.window)

        Settings {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppIdentity.name)
                    .font(.title2.bold())
                Text("The local dictation engine will be configured in the next build stage.")
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(width: 480, height: 180)
        }
    }
}

import AppKit
import SwiftUI
import MeetingDetection

@MainActor
private final class ReportModel: ObservableObject {
    @Published var text = ""
    @Published var status = "Review the report, describe the expected behavior, and remove anything you do not want to share."

    func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MeetingBusy-detection-report.txt"
        panel.title = "Save reviewed detection report"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Data(text.utf8).write(to: url, options: .atomic); status = "Report saved locally. Share it yourself if you choose." }
        catch { status = "The report could not be saved. Choose another location and try again." }
    }
}

@MainActor
final class ReportController {
    private let model = ReportModel()
    private var window: NSWindow?

    func show(_ report: DetectionReport) {
        if let window, window.isVisible { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); return }
        model.text = report.rendered()
        model.status = "Review the report, describe the expected behavior, and remove anything you do not want to share."
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 580),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Review detection report"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ReportView(model: model))
            window.minSize = NSSize(width: 500, height: 400)
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct ReportView: View {
    @ObservedObject var model: ReportModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This detection is incorrect").font(.title2.bold())
            Text("This report includes app version, detection state, enabled services, signals, and error codes. It excludes meeting content, custom indicator text, user paths, and logs.")
                .font(.callout)
            TextEditor(text: $model.text).font(.system(.body, design: .monospaced))
                .accessibilityLabel("Editable diagnostic report")
                .border(Color.secondary.opacity(0.3))
            Text(model.status).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Save reviewed report…") { model.save() }
                Spacer()
                Text("Nothing is submitted automatically.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(20).frame(minWidth: 460, minHeight: 350)
    }
}

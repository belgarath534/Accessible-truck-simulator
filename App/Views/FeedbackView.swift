import SwiftUI
import UIKit

/// Send Feedback: type a message, and it opens as a new report on the game's GitHub page,
/// with the game version and device filled in.
struct FeedbackView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case bug = "Something's broken", idea = "An idea", other = "Something else"
        var id: String { rawValue }
        var label: String { self == .bug ? "bug" : self == .idea ? "idea" : "feedback" }
    }

    @Environment(\.openURL) private var openURL
    @State private var kind = Kind.bug
    @State private var message = ""

    static let reportsPage = "https://github.com/belgarath534/Accessible-truck-simulator/issues"

    private var details: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let device = UIDevice.current
        return "Game \(version) (\(build)), \(device.model), iOS \(device.systemVersion)"
    }

    private var reportURL: URL? {
        let firstLine = message.split(separator: "\n").first.map(String.init) ?? ""
        let title = "[\(kind.label)] " + String(firstLine.prefix(70))
        var parts = URLComponents(string: Self.reportsPage + "/new")
        parts?.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "body", value: message + "\n\n---\n" + details),
        ]
        return parts?.url
    }

    var body: some View {
        Form {
            Section {
                Picker("What is it about?", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                TextEditor(text: $message)
                    .frame(minHeight: 140)
                    .accessibilityLabel("Your message")
                    .accessibilityHint("Tell us what happened or what you'd like.")
            } footer: {
                Text("Send opens the game's page on GitHub with your message and your game version filled in. You need a free GitHub account to post it. Everyone can read reports there, so don't include private details.")
            }
            Section {
                Button("Send") { if let url = reportURL { openURL(url) } }
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Read other players' reports") { if let url = URL(string: Self.reportsPage) { openURL(url) } }
            }
        }
        .navigationTitle("Send Feedback")
    }
}

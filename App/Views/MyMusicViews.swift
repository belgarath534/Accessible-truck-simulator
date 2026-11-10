import MediaPlayer
import SwiftUI
import UniformTypeIdentifiers

/// Apple's music library picker, for choosing Apple Music songs for the truck radio.
struct AppleMusicPicker: UIViewControllerRepresentable {
    let onPick: ([MPMediaItem]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> MPMediaPickerController {
        let picker = MPMediaPickerController(mediaTypes: .music)
        picker.allowsPickingMultipleItems = true
        picker.showsCloudItems = true
        picker.prompt = "Pick songs for the truck radio"
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: MPMediaPickerController, context: Context) {}

    final class Coordinator: NSObject, MPMediaPickerControllerDelegate {
        let onPick: ([MPMediaItem]) -> Void
        init(onPick: @escaping ([MPMediaItem]) -> Void) { self.onPick = onPick }

        func mediaPicker(_ picker: MPMediaPickerController, didPickMediaItems collection: MPMediaItemCollection) {
            onPick(collection.items)
            picker.dismiss(animated: true)
        }

        func mediaPickerDidCancel(_ picker: MPMediaPickerController) { picker.dismiss(animated: true) }
    }
}

/// Settings, Truck Radio: where the music comes from, plus picking Apple Music songs or importing files.
struct RadioSourceSection: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var showingPicker = false
    @State private var showingImporter = false
    @State private var files: [URL] = MusicPlayer.shared.myFiles
    @State private var appleTitles: [String] = MusicPlayer.shared.appleMusicTitles
    @State private var message: String?

    var body: some View {
        Section {
            Picker("Radio plays", selection: $settings.radioSource) {
                ForEach(RadioSource.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            switch settings.radioSource {
            case .gameRadio:
                EmptyView()
            case .myFiles:
                Button("Add Music Files") { showingImporter = true }
                    .accessibilityHint("Pick MP3, M4A or WAV files from the Files app, iCloud Drive or other storage. They're copied into the game.")
                ForEach(files, id: \.self) { url in
                    Text(url.deletingPathExtension().lastPathComponent)
                        .swipeActions {
                            Button("Remove", role: .destructive) { remove(url) }
                        }
                        .accessibilityAction(named: "Remove") { remove(url) }
                }
            case .appleMusic:
                Button(appleTitles.isEmpty ? "Choose Songs from Apple Music" : "Choose Different Songs") { chooseAppleMusic() }
                    .accessibilityHint("Pick songs from your music library to play on the truck radio.")
                ForEach(Array(appleTitles.enumerated()), id: \.offset) { Text($0.element) }
            }
        } header: {
            Text("Truck radio")
        } footer: {
            switch settings.radioSource {
            case .gameRadio:
                Text("The game's own songs, with the Big Rig Radio DJ between them.")
            case .myFiles:
                Text(files.isEmpty ? "No files yet: add some, or the radio stays quiet." :
                        "\(files.count) song\(files.count == 1 ? "" : "s"). Swipe or use the Remove action to take one out. The music gets quieter while the game talks.")
            case .appleMusic:
                Text("Songs from your library. They need to be downloaded or in your Apple Music subscription. Apple doesn't let games turn this music down, so the game talks over it.")
            }
        }
        .sheet(isPresented: $showingPicker) {
            AppleMusicPicker { items in
                MusicPlayer.shared.setAppleMusicSongs(items)
                appleTitles = MusicPlayer.shared.appleMusicTitles
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            if case let .success(urls) = result {
                let added = MusicPlayer.shared.importFiles(urls)
                files = MusicPlayer.shared.myFiles
                message = "Added \(added) song\(added == 1 ? "" : "s") to the truck radio."
            }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private func remove(_ url: URL) {
        MusicPlayer.shared.removeFile(url)
        files = MusicPlayer.shared.myFiles
    }

    private func chooseAppleMusic() {
        MPMediaLibrary.requestAuthorization { status in
            DispatchQueue.main.async {
                if status == .authorized {
                    showingPicker = true
                } else {
                    message = "The game needs permission to use your music library. Turn it on in the iPhone's Settings, Truck Sim, Media and Apple Music."
                }
            }
        }
    }
}

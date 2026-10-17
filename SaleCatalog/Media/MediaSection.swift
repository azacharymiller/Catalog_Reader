import AVKit
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Photos and video attached to a hip, from the camera or the photo library.
struct MediaSection: View {
    @Bindable var hip: Hip
    @Environment(\.modelContext) private var context
    @AppStorage("authorName") private var author = ""
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var playing: PlayingVideo?
    @State private var viewing: MediaItem?

    private var items: [MediaItem] { hip.media.sorted { $0.createdAt < $1.createdAt } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Photos and video").font(.headline)
                Spacer()
                PhotosPicker(selection: $pickerItems, matching: .any(of: [.images, .videos])) {
                    Label("Library", systemImage: "photo.on.rectangle")
                }
                Button { showCamera = true } label: { Label("Camera", systemImage: "camera") }
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
            }
            if items.isEmpty {
                Text("None yet").foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(items) { item in
                            thumbnail(item)
                        }
                    }
                }
            }
        }
        .onChange(of: pickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                for item in newItems { await importPicked(item) }
                pickerItems = []
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView(onCapture: { url, kind in add(fileName: url.lastPathComponent, kind: kind) },
                       onDone: { showCamera = false })
                .ignoresSafeArea()
        }
        .sheet(item: $playing) { video in
            VideoPlayer(player: AVPlayer(url: video.url))
        }
        .sheet(item: $viewing) { item in
            if let image = UIImage(contentsOfFile: item.url.path) {
                Image(uiImage: image).resizable().scaledToFit()
            }
        }
    }

    @ViewBuilder
    private func thumbnail(_ item: MediaItem) -> some View {
        Button {
            if item.kind == "video" { playing = PlayingVideo(url: item.url) } else { viewing = item }
        } label: {
            ZStack {
                if item.kind == "photo", let image = UIImage(contentsOfFile: item.url.path) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "play.circle.fill").font(.largeTitle)
                }
            }
            .frame(width: 140, height: 105)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .bottomLeading) {
                Text(item.author).font(.caption2).padding(4)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                    .padding(4)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive) {
                try? FileManager.default.removeItem(at: item.url)
                context.delete(item)
            }
        }
    }

    private func importPicked(_ item: PhotosPickerItem) async {
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
            if let movie = try? await item.loadTransferable(type: PickedMovie.self) {
                add(fileName: movie.url.lastPathComponent, kind: "video")
            }
        } else if let data = try? await item.loadTransferable(type: Data.self) {
            let name = "media-\(UUID().uuidString).jpg"
            let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.85) ?? data
            if (try? jpeg.write(to: AppFiles.url(name))) != nil {
                add(fileName: name, kind: "photo")
            }
        }
    }

    private func add(fileName: String, kind: String) {
        let media = MediaItem(author: author, kind: kind, fileName: fileName)
        context.insert(media)
        media.hip = hip
        try? context.save()
    }
}

struct PlayingVideo: Identifiable {
    let url: URL
    var id: URL { url }
}

/// A video from the photo library, copied into the app's own storage.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let destination = AppFiles.url("media-\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedMovie(url: destination)
        }
    }
}

/// The system camera, for photos and video.
struct CameraView: UIViewControllerRepresentable {
    var onCapture: (URL, String) -> Void
    var onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView

        init(_ parent: CameraView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let video = info[.mediaURL] as? URL {
                let destination = AppFiles.url("media-\(UUID().uuidString).\(video.pathExtension)")
                if (try? FileManager.default.copyItem(at: video, to: destination)) != nil {
                    parent.onCapture(destination, "video")
                }
            } else if let image = info[.originalImage] as? UIImage,
                      let data = image.jpegData(compressionQuality: 0.85) {
                let destination = AppFiles.url("media-\(UUID().uuidString).jpg")
                if (try? data.write(to: destination)) != nil {
                    parent.onCapture(destination, "photo")
                }
            }
            parent.onDone()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onDone()
        }
    }
}

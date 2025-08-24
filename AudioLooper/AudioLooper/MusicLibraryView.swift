import SwiftUI
import MediaPlayer
import AVFoundation

struct MusicLibraryView: View {
    @StateObject private var musicManager = MusicLibraryManager()
    @Environment(\.dismiss) var dismiss
    let onAudioSelected: (URL) -> Void
    
    @State private var searchText = ""
    @State private var showingAuthAlert = false
    @State private var isExporting = false
    @State private var exportingItem: MPMediaItem?
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    
    var filteredItems: [MPMediaItem] {
        if searchText.isEmpty {
            return musicManager.musicItems
        } else {
            return musicManager.musicItems.filter { item in
                (item.title?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (item.artist?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (item.albumTitle?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if musicManager.authorizationStatus != .authorized {
                    unauthorizedView
                } else if musicManager.isLoading {
                    loadingView
                } else if musicManager.musicItems.isEmpty {
                    emptyStateView
                } else {
                    musicListView
                }
            }
            .navigationTitle(NSLocalizedString("music_library", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("cancel", comment: "")) {
                        dismiss()
                    }
                }
                
                if musicManager.authorizationStatus == .authorized && !musicManager.musicItems.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(NSLocalizedString("refresh", comment: "")) {
                            musicManager.loadMusicLibrary()
                        }
                    }
                }
            }
            .alert(NSLocalizedString("authorization_required", comment: ""), isPresented: $showingAuthAlert) {
                Button(NSLocalizedString("settings", comment: "")) {
                    if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsUrl)
                    }
                }
                Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("settings_access_message", comment: ""))
            }
            .alert(NSLocalizedString("export_error", comment: ""), isPresented: $showingErrorAlert) {
                Button(NSLocalizedString("ok", comment: ""), role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private var unauthorizedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.list")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text(NSLocalizedString("music_library_access", comment: ""))
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(NSLocalizedString("music_library_access_message", comment: ""))
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            Button(NSLocalizedString("request_access", comment: "")) {
                Task {
                    let authorized = await musicManager.requestAuthorization()
                    if authorized {
                        musicManager.loadMusicLibrary()
                    } else {
                        showingAuthAlert = true
                    }
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text(NSLocalizedString("loading_music_library", comment: ""))
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.house")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text(NSLocalizedString("no_compatible_music_found", comment: ""))
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("only_non_drm_music_info", comment: ""))
                    .font(.body)
                    .foregroundColor(.secondary)
                
                Text("• " + NSLocalizedString("music_purchased_itunes", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("• " + NSLocalizedString("music_imported_cds", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("• " + NSLocalizedString("drm_free_audio_files", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            Button(NSLocalizedString("refresh_library", comment: "")) {
                musicManager.loadMusicLibrary()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
    
    private var musicListView: some View {
        VStack {
            SearchBar(text: $searchText)
                .padding(.horizontal)
            
            List {
                ForEach(filteredItems, id: \.persistentID) { item in
                    MusicItemRow(
                        item: item,
                        isExporting: exportingItem?.persistentID == item.persistentID && isExporting
                    ) {
                        exportAudio(item: item)
                    }
                }
            }
            .listStyle(PlainListStyle())
        }
        .onAppear {
            if musicManager.musicItems.isEmpty {
                musicManager.loadMusicLibrary()
            }
        }
    }
    
    private func exportAudio(item: MPMediaItem) {
        isExporting = true
        exportingItem = item
        
        musicManager.exportAudioFile(from: item) { result in
            DispatchQueue.main.async {
                self.isExporting = false
                self.exportingItem = nil
                
                switch result {
                case .success(let url):
                    self.onAudioSelected(url)
                    self.dismiss()
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.showingErrorAlert = true
                }
            }
        }
    }
}

struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField(NSLocalizedString("search_music", comment: ""), text: $text)
                .textFieldStyle(PlainTextFieldStyle())
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct MusicItemRow: View {
    let item: MPMediaItem
    let isExporting: Bool
    let onSelect: () -> Void
    
    var body: some View {
        HStack {
            AsyncImage(url: nil) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundColor(.gray)
                    )
            }
            .frame(width: 50, height: 50)
            .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title ?? NSLocalizedString("unknown_title", comment: ""))
                    .font(.headline)
                    .lineLimit(1)
                
                if let artist = item.artist {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                if let album = item.albumTitle {
                    Text(album)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                HStack {
                    let duration = item.playbackDuration
                    if duration > 0 {
                        Text(formatDuration(duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if let assetURL = item.assetURL {
                        let asset = AVAsset(url: assetURL)
                        if asset.hasProtectedContent {
                            Image(systemName: "lock.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                    }
                }
            }
            
            Spacer()
            
            if isExporting {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Button(action: onSelect) {
                    Text(NSLocalizedString("import", comment: ""))
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(isExporting)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    MusicLibraryView { url in
        print("Selected audio: \(url)")
    }
}
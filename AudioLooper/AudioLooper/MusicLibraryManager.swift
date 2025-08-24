import SwiftUI
import MediaPlayer
import AVFoundation

class MusicLibraryManager: NSObject, ObservableObject {
    @Published var musicItems: [MPMediaItem] = []
    @Published var isLoading = false
    @Published var authorizationStatus: MPMediaLibraryAuthorizationStatus = .notDetermined
    
    override init() {
        super.init()
        checkAuthorizationStatus()
    }
    
    func checkAuthorizationStatus() {
        authorizationStatus = MPMediaLibrary.authorizationStatus()
    }
    
    func requestAuthorization() async -> Bool {
        let status = await MPMediaLibrary.requestAuthorization()
        await MainActor.run {
            self.authorizationStatus = status
        }
        return status == .authorized
    }
    
    func loadMusicLibrary() {
        guard authorizationStatus == .authorized else { return }
        
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let query = MPMediaQuery.songs()
            
            // Filter for non-protected audio files (purchased, not DRM-protected)
            let predicate = MPMediaPropertyPredicate(
                value: false,
                forProperty: MPMediaItemPropertyIsCloudItem
            )
            query.addFilterPredicate(predicate)
            
            // Only get items that can be exported
            let items = query.items?.filter { item in
                // Check if the item is available for export (not DRM protected)
                guard let assetURL = item.assetURL else { return false }
                return self.canExportAudio(from: assetURL)
            } ?? []
            
            DispatchQueue.main.async {
                self.musicItems = items
                self.isLoading = false
            }
        }
    }
    
    private func canExportAudio(from url: URL) -> Bool {
        let asset = AVAsset(url: url)
        return asset.isExportable && !asset.hasProtectedContent
    }
    
    func exportAudioFile(from mediaItem: MPMediaItem, completion: @escaping (Result<URL, Error>) -> Void) {
        guard let assetURL = mediaItem.assetURL else {
            completion(.failure(AudioExportError.invalidURL))
            return
        }
        
        let asset = AVAsset(url: assetURL)
        
        guard asset.isExportable && !asset.hasProtectedContent else {
            completion(.failure(AudioExportError.protectedContent))
            return
        }
        
        // Create export session
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            completion(.failure(AudioExportError.exportSessionFailed))
            return
        }
        
        // Set up output URL
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputURL = documentsPath.appendingPathComponent("exported_\(UUID().uuidString).m4a")
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        
        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                switch exportSession.status {
                case .completed:
                    completion(.success(outputURL))
                case .failed:
                    completion(.failure(exportSession.error ?? AudioExportError.exportFailed))
                case .cancelled:
                    completion(.failure(AudioExportError.exportCancelled))
                default:
                    completion(.failure(AudioExportError.unknown))
                }
            }
        }
    }
}

enum AudioExportError: LocalizedError {
    case invalidURL
    case protectedContent
    case exportSessionFailed
    case exportFailed
    case exportCancelled
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return NSLocalizedString("Invalid audio URL", comment: "")
        case .protectedContent:
            return NSLocalizedString("This audio file is protected and cannot be exported", comment: "")
        case .exportSessionFailed:
            return NSLocalizedString("Failed to create export session", comment: "")
        case .exportFailed:
            return NSLocalizedString("Audio export failed", comment: "")
        case .exportCancelled:
            return NSLocalizedString("Audio export was cancelled", comment: "")
        case .unknown:
            return NSLocalizedString("Unknown error occurred during export", comment: "")
        }
    }
}
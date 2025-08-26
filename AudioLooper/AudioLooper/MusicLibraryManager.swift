import SwiftUI
import MediaPlayer
import AVFoundation

class MusicLibraryManager: NSObject, ObservableObject {
    @Published var musicItems: [MPMediaItem] = []
    @Published var isLoading = false
    @Published var authorizationStatus: MPMediaLibraryAuthorizationStatus = .notDetermined
    @Published var exportProgress: Double = 0.0
    
    private var currentExportTask: Task<Void, Never>?
    
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
        
        Task {
            let query = MPMediaQuery.songs()
            
            // Filter for non-protected audio files (purchased, not DRM-protected)
            let predicate = MPMediaPropertyPredicate(
                value: false,
                forProperty: MPMediaItemPropertyIsCloudItem
            )
            query.addFilterPredicate(predicate)
            
            // Only get items that can be exported
            var exportableItems: [MPMediaItem] = []
            
            for item in query.items ?? [] {
                guard let assetURL = item.assetURL else { continue }
                if await self.canExportAudioAsync(from: assetURL) {
                    exportableItems.append(item)
                }
            }
            
            await MainActor.run {
                self.musicItems = exportableItems
                self.isLoading = false
            }
        }
    }
    
    private func canExportAudio(from url: URL) -> Bool {
        let asset = AVAsset(url: url)
        return asset.isExportable && !asset.hasProtectedContent
    }
    
    private func canExportAudioAsync(from url: URL) async -> Bool {
        let asset = AVAsset(url: url)
        do {
            let isExportable = try await asset.load(.isExportable)
            let hasProtectedContent = try await asset.load(.hasProtectedContent)
            return isExportable && !hasProtectedContent
        } catch {
            return false
        }
    }
    
    func exportAudioFile(from mediaItem: MPMediaItem, completion: @escaping (Result<URL, Error>) -> Void) {
        // Cancel any existing export task
        currentExportTask?.cancel()
        
        currentExportTask = Task {
            await self.performExport(from: mediaItem, completion: completion)
        }
    }
    
    @MainActor
    private func performExport(from mediaItem: MPMediaItem, completion: @escaping (Result<URL, Error>) -> Void) async {
        guard let assetURL = mediaItem.assetURL else {
            completion(.failure(AudioExportError.invalidURL))
            return
        }
        
        let asset = AVAsset(url: assetURL)
        
        // Check if asset is exportable and not protected
        do {
            let isExportable = try await asset.load(.isExportable)
            let hasProtectedContent = try await asset.load(.hasProtectedContent)
            
            guard isExportable && !hasProtectedContent else {
                completion(.failure(AudioExportError.protectedContent))
                return
            }
        } catch {
            completion(.failure(error))
            return
        }
        
        // Create export session
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            completion(.failure(AudioExportError.exportSessionFailed))
            return
        }
        
        // Set up output URL
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = generateFileName(for: mediaItem)
        let outputURL = documentsPath.appendingPathComponent(fileName)
        
        // Remove existing file if it exists
        try? FileManager.default.removeItem(at: outputURL)
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        
        // Check available disk space
        do {
            let resources = try outputURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let availableCapacity = resources.volumeAvailableCapacityForImportantUsage, availableCapacity < 50_000_000 { // 50MB
                completion(.failure(AudioExportError.insufficientStorage))
                return
            }
        } catch {
            print("Could not check disk space: \(error)")
        }
        
        // Start progress monitoring
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                self.exportProgress = Double(exportSession.progress)
            }
        }
        
        do {
            // Use new async export method
            try await exportSession.export()
            
            progressTimer.invalidate()
            self.exportProgress = 1.0
            
            completion(.success(outputURL))
        } catch {
            progressTimer.invalidate()
            self.exportProgress = 0.0
            
            // Clean up failed export
            try? FileManager.default.removeItem(at: outputURL)
            
            completion(.failure(error))
        }
    }
    
    private func generateFileName(for mediaItem: MPMediaItem) -> String {
        let title = mediaItem.title?.replacingOccurrences(of: "/", with: "-") ?? "Unknown"
        let artist = mediaItem.artist?.replacingOccurrences(of: "/", with: "-") ?? "Unknown"
        let timestamp = Date().timeIntervalSince1970
        return "\(artist) - \(title) - \(Int(timestamp)).m4a"
    }
    
    func cancelExport() {
        currentExportTask?.cancel()
        exportProgress = 0.0
    }
}

enum AudioExportError: LocalizedError {
    case invalidURL
    case protectedContent
    case exportSessionFailed
    case exportFailed
    case exportCancelled
    case insufficientStorage
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
        case .insufficientStorage:
            return NSLocalizedString("Insufficient storage space for export", comment: "")
        case .unknown:
            return NSLocalizedString("Unknown error occurred during export", comment: "")
        }
    }
}
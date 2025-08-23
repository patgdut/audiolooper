import Foundation
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import Photos

@MainActor
class AudioLooperManager: NSObject, ObservableObject {
    // 保持对 coordinator 的强引用
    private var documentPickerCoordinator: DocumentPickerCoordinator?
    private var photoPickerCoordinator: PhotoPickerCoordinator?
    
    @Published var selectedAudioURL: URL?
    @Published var audioDuration: TimeInterval = 0
    @Published var startTime: TimeInterval = 0
    @Published var endTime: TimeInterval = 0
    @Published var isProcessing = false
    @Published var progress: Double = 0
    @Published var currentTask = ""
    @Published var loopCount: Int = 1
    
    private var exportSession: AVAssetExportSession?
    
    // Audio format options
    enum AudioFormat: String, CaseIterable {
        case m4a = "m4a"
        case mp3 = "mp3"
        case wav = "wav"
        case aac = "aac"
        
        var displayName: String {
            switch self {
            case .m4a: return "M4A"
            case .mp3: return "MP3"
            case .wav: return "WAV"
            case .aac: return "AAC"
            }
        }
        
        var fileExtension: String {
            switch self {
            case .m4a: return "m4a"
            case .mp3: return "m4a" // iOS限制，实际输出M4A
            case .wav: return "wav"
            case .aac: return "m4a" // AAC包含在M4A容器中
            }
        }
        
        var exportPreset: String {
            switch self {
            case .m4a: return AVAssetExportPresetAppleM4A
            case .mp3: return AVAssetExportPresetAppleM4A // iOS限制，实际导出M4A格式
            case .wav: return AVAssetExportPresetPassthrough // WAV使用直通预设
            case .aac: return AVAssetExportPresetAppleM4A // AAC包含在M4A容器中
            }
        }
        
        var outputFileType: AVFileType {
            switch self {
            case .m4a, .aac: return .m4a
            case .mp3: return .m4a // iOS限制，实际输出M4A
            case .wav: return .wav // WAV格式
            }
        }
        
        var description: String {
            switch self {
            case .m4a: return NSLocalizedString("m4a_format_description", comment: "M4A format description")
            case .mp3: return NSLocalizedString("mp3_format_description", comment: "MP3 format description")  
            case .wav: return NSLocalizedString("wav_format_description", comment: "WAV format description")
            case .aac: return NSLocalizedString("aac_format_description", comment: "AAC format description")
            }
        }
    }
    
    func selectAudio() {
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [
            UTType.movie,
            UTType.video,
            UTType.mpeg4Movie,
            UTType.quickTimeMovie,
            UTType.avi,
            UTType.mpeg,
            UTType.audio,
            UTType("public.mp3") ?? UTType.audio,
            UTType("public.wav") ?? UTType.audio,
            UTType("public.m4a") ?? UTType.audio,
            UTType("public.aac-audio") ?? UTType.audio
        ])
        documentPicker.allowsMultipleSelection = false
        documentPickerCoordinator = DocumentPickerCoordinator(manager: self)
        documentPicker.delegate = documentPickerCoordinator
        documentPicker.modalPresentationStyle = UIModalPresentationStyle.formSheet
        
        // Configure popover for iPad
        PopoverHelper.configurePopover(documentPicker.popoverPresentationController)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(documentPicker, animated: true)
        }
    }
    
    func selectAudioFromPhotos() {
        checkPhotoLibraryPermission { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.presentPhotosPicker()
                } else {
                    self?.showPermissionAlert()
                }
            }
        }
    }
    
    private func checkPhotoLibraryPermission(completion: @escaping (Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        switch status {
        case .authorized, .limited:
            completion(true)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                completion(newStatus == .authorized || newStatus == .limited)
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }
    
    private func presentPhotosPicker() {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .any(of: [.videos])
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current
        config.selection = .ordered
        config.mode = .default
        config.preselectedAssetIdentifiers = []
        
        let picker = PHPickerViewController(configuration: config)
        photoPickerCoordinator = PhotoPickerCoordinator(manager: self)
        picker.delegate = photoPickerCoordinator
        picker.modalPresentationStyle = UIModalPresentationStyle.formSheet
        
        // Configure popover for iPad
        PopoverHelper.configurePopover(picker.popoverPresentationController)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(picker, animated: true)
        }
    }
    
    func showErrorAlert(message: String) {
        let alert = UIAlertController(
            title: "Error",
            message: message,
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("ok", comment: "OK button"), style: .default))
        
        // Configure popover for iPad
        PopoverHelper.configurePopover(alert.popoverPresentationController)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(alert, animated: true)
        }
    }
    
    private func showPermissionAlert() {
        let alert = UIAlertController(
            title: NSLocalizedString("photo_library_access_required", comment: "Photo library access required title"),
            message: NSLocalizedString("photo_library_permission_message", comment: "Photo library permission message"),
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("settings", comment: "Settings button"), style: .default) { _ in
            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsUrl)
            }
        })
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("cancel", comment: "Cancel button"), style: .cancel))
        
        // Configure popover for iPad
        PopoverHelper.configurePopover(alert.popoverPresentationController)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(alert, animated: true)
        }
    }
    
    func loadAudioInfo(from url: URL) {
        // 只有来自文档选择器的外部文件才需要安全作用域访问权限
        // 应用内临时文件和沙盒内文件不需要
        let isAppSandboxFile = url.path.contains(Bundle.main.bundleIdentifier ?? "") || 
                              url.path.contains("/tmp/") || 
                              url.path.contains("/Library/") ||
                              url.path.contains("/Documents/")
        
        let needsSecurityScope = url.isFileURL && !isAppSandboxFile && 
                                !url.path.hasPrefix(FileManager.default.temporaryDirectory.path)
        
        var hasSecurityAccess = false
        if needsSecurityScope {
            hasSecurityAccess = url.startAccessingSecurityScopedResource()
            if !hasSecurityAccess {
                print("Failed to access security scoped resource for URL: \(url)")
                // 继续尝试，某些情况下仍可能成功
            }
        }
        
        defer {
            if needsSecurityScope && hasSecurityAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        let asset = AVURLAsset(url: url)
        Task {
            do {
                let duration = try await asset.load(.duration)
                await MainActor.run {
                    self.selectedAudioURL = url
                    self.audioDuration = CMTimeGetSeconds(duration)
                    
                    // Set initial range with default free user setting
                    // The UI layer will call setInitialTimeRange again with correct subscription status
                    self.setInitialTimeRange(isSubscribed: false)
                }
            } catch {
                print("Failed to load video duration: \(error)")
                await MainActor.run {
                    self.showErrorAlert(message: NSLocalizedString("failed_to_load_audio", comment: "Failed to load audio error"))
                }
            }
        }
    }
    
    func setInitialTimeRange(isSubscribed: Bool = false) {
        startTime = 0
        
        if isSubscribed {
            // Premium users get full audio by default
            endTime = audioDuration
        } else {
            // Free users limited to 30 seconds
            endTime = min(audioDuration, 30)
        }
        
        // Force a range update by slightly modifying the values to trigger UI refresh
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // This will trigger the UI to update and show the first frame
            let tempStart = self.startTime
            let tempEnd = self.endTime
            
            // Trigger change notifications
            self.startTime = tempStart + 0.01
            self.endTime = tempEnd
            
            // Reset to correct values
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.startTime = tempStart
            }
        }
    }
    
    func loopAudio(format: AudioFormat = .m4a, completion: @escaping (Result<URL, Error>) -> Void) {
        guard let audioURL = selectedAudioURL else {
            completion(.failure(AudioLoopError.noAudioSelected))
            return
        }
        
        isProcessing = true
        progress = 0
        currentTask = NSLocalizedString("preparing_audio_loop", comment: "Preparing audio loop message")
        
        let asset = AVURLAsset(url: audioURL)
        
        // Create time range for extraction
        let startTimeCM = CMTime(seconds: startTime, preferredTimescale: 600)
        let endTimeCM = CMTime(seconds: endTime, preferredTimescale: 600)
        let timeRange = CMTimeRange(start: startTimeCM, end: endTimeCM)
        
        // Create output URL for looped audio
        let finalFileName = "looped_audio_\(Int(Date().timeIntervalSince1970)).\(format.fileExtension)"
        let finalURL = getDocumentsDirectory().appendingPathComponent(finalFileName)
        
        // Remove existing file if any
        try? FileManager.default.removeItem(at: finalURL)
        
        // Create composition for looped audio
        createLoopedAudioComposition(asset: asset, timeRange: timeRange, outputURL: finalURL, format: format, completion: completion)
    }
    
    private func createLoopedAudioComposition(asset: AVURLAsset, timeRange: CMTimeRange, outputURL: URL, format: AudioFormat, completion: @escaping (Result<URL, Error>) -> Void) {
        // Performance optimization: Limit maximum loops to prevent memory issues
        let maxAllowedLoops = 50
        let actualLoopCount = min(loopCount, maxAllowedLoops)
        
        if loopCount > maxAllowedLoops {
            print("Warning: Loop count limited to \(maxAllowedLoops) for performance reasons")
        }
        
        // Create composition
        let composition = AVMutableComposition()
        
        guard let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            isProcessing = false
            completion(.failure(AudioLoopError.compositionCreationFailed))
            return
        }
        
        Task {
            do {
                // Get source tracks
                let sourceAudioTracks = try await asset.loadTracks(withMediaType: .audio)
                
                guard let sourceAudioTrack = sourceAudioTracks.first else {
                    await MainActor.run {
                        self.isProcessing = false
                        completion(.failure(AudioLoopError.noAudioTrackFound))
                    }
                    return
                }
                
                // Create looped composition
                var currentTime = CMTime.zero
                let segmentDuration = timeRange.duration
                
                for i in 0..<actualLoopCount {
                    // Add audio segment
                    try audioTrack.insertTimeRange(timeRange, of: sourceAudioTrack, at: currentTime)
                    
                    currentTime = CMTimeAdd(currentTime, segmentDuration)
                    
                    // Update progress
                    await MainActor.run {
                        self.progress = Double(i + 1) / Double(actualLoopCount) * 0.7 // 70% for composition
                        self.currentTask = String(format: NSLocalizedString("creating_loop", comment: "Creating loop progress message"), i + 1, actualLoopCount)
                    }
                }
                
                // Export the composition
                await exportComposition(composition: composition, outputURL: outputURL, format: format, completion: completion)
                
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    completion(.failure(error))
                }
            }
        }
    }
    
    private func exportComposition(composition: AVMutableComposition, outputURL: URL, format: AudioFormat, completion: @escaping (Result<URL, Error>) -> Void) async {
        // Use appropriate audio preset based on format
        let exportPreset = format.exportPreset
        
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: exportPreset) else {
            await MainActor.run {
                self.isProcessing = false
                completion(.failure(AudioLoopError.exportSessionCreationFailed))
            }
            return
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = format.outputFileType
        
        self.exportSession = exportSession
        
        await MainActor.run {
            self.currentTask = NSLocalizedString("exporting_looped_audio", comment: "Exporting looped audio message")
        }
        
        // Monitor progress
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                self.progress = 0.7 + (Double(exportSession.progress) * 0.3) // Start from 70%
            }
        }
        
        await exportSession.export()
        
        await MainActor.run {
            progressTimer.invalidate()
            self.isProcessing = false
            self.progress = 1.0
            self.currentTask = ""
            
            switch exportSession.status {
            case .completed:
                completion(.success(outputURL))
            case .failed:
                completion(.failure(exportSession.error ?? AudioLoopError.exportFailed))
            case .cancelled:
                completion(.failure(AudioLoopError.exportCancelled))
            default:
                completion(.failure(AudioLoopError.exportFailed))
            }
        }
    }
    
    
    func cancelExport() {
        exportSession?.cancelExport()
        isProcessing = false
        progress = 0
        currentTask = ""
        
        // Clear memory
        cleanupTempFiles()
    }
    
    private func cleanupTempFiles() {
        // Clean up temporary files to free memory
        let tempDirectory = FileManager.default.temporaryDirectory
        do {
            let tempFiles = try FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)
            for file in tempFiles {
                if file.pathExtension == "m4a" || file.pathExtension == "mp3" || file.pathExtension == "wav" {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        } catch {
            print("Failed to clean up temp files: \(error)")
        }
    }
    
    
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    // Helper methods for time formatting
    func formattedTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var selectedDuration: TimeInterval {
        return endTime - startTime
    }
}

// Document picker coordinator
class DocumentPickerCoordinator: NSObject, UIDocumentPickerDelegate {
    let manager: AudioLooperManager
    
    init(manager: AudioLooperManager) {
        self.manager = manager
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        manager.loadAudioInfo(from: url)
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        // Handle cancellation
        // The picker will dismiss itself automatically
    }
}

// Photo picker coordinator
class PhotoPickerCoordinator: NSObject, PHPickerViewControllerDelegate {
    let manager: AudioLooperManager
    
    init(manager: AudioLooperManager) {
        self.manager = manager
    }
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        // 主动关闭选择器
        picker.dismiss(animated: true) {
            // 在关闭后处理结果
            guard let result = results.first else {
                // 用户取消或未选择
                return
            }
            
            self.processSelectedVideo(result: result)
        }
    }
    
    private func processSelectedVideo(result: PHPickerResult) {
        // 检查是否支持音频或视频
        let hasAudio = result.itemProvider.hasItemConformingToTypeIdentifier(UTType.audio.identifier)
        let hasVideo = result.itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
        
        guard hasAudio || hasVideo else {
            DispatchQueue.main.async { [weak self] in
                self?.manager.showErrorAlert(message: NSLocalizedString("select_valid_audio_or_video", comment: "Select valid audio or video error"))
            }
            return
        }
        
        // 加载音频或视频文件
        let typeIdentifier = hasVideo ? UTType.movie.identifier : UTType.audio.identifier
        result.itemProvider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] url, error in
            guard let self = self, let url = url, error == nil else {
                print("Error loading file: \(error?.localizedDescription ?? "Unknown error")")
                DispatchQueue.main.async { [weak self] in
                    self?.manager.showErrorAlert(message: "Failed to load selected file. Please try again.")
                }
                return
            }
            
            // Copy the file to a temporary location since the original URL might be temporary
            let tempDir = FileManager.default.temporaryDirectory
            let tempURL = tempDir.appendingPathComponent(url.lastPathComponent)
            
            do {
                // Remove existing temp file if any
                try? FileManager.default.removeItem(at: tempURL)
                try FileManager.default.copyItem(at: url, to: tempURL)
                
                DispatchQueue.main.async { [weak self] in
                    self?.manager.loadAudioInfo(from: tempURL)
                }
            } catch {
                print("Error copying file: \(error)")
                DispatchQueue.main.async { [weak self] in
                    self?.manager.showErrorAlert(message: "Failed to process selected file. Please try again.")
                }
            }
        }
    }
    
    private func showErrorAlert(message: String) {
        let alert = UIAlertController(
            title: "Error",
            message: message,
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("ok", comment: "OK button"), style: .default))
        
        // Configure popover for iPad
        PopoverHelper.configurePopover(alert.popoverPresentationController)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(alert, animated: true)
        }
    }
}

// Custom errors
enum AudioLoopError: LocalizedError {
    case noAudioSelected
    case compositionCreationFailed
    case noAudioTrackFound
    case exportSessionCreationFailed
    case exportFailed
    case exportCancelled
    
    var errorDescription: String? {
        switch self {
        case .noAudioSelected:
            return "No audio file selected"
        case .compositionCreationFailed:
            return "Failed to create audio composition"
        case .noAudioTrackFound:
            return "No audio track found in selected file"
        case .exportSessionCreationFailed:
            return "Failed to create export session"
        case .exportFailed:
            return "Audio loop creation failed"
        case .exportCancelled:
            return "Audio loop creation was cancelled"
        }
    }
} 
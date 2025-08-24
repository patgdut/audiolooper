import SwiftUI
import MessageUI

struct AudioLooperView: View {
    @StateObject private var audioLooperManager = AudioLooperManager()
    @EnvironmentObject var purchaseModel: PurchaseModel
    
    @State private var showingShare = false
    @State private var showPurchaseView = false
    @State private var showingPaywallAlert = false
    @State private var showingMailComposer = false
    @State private var showingEmailAlert = false
    @State private var showingExtractionResultAlert = false
    @State private var extractionResultMessage = ""
    @State private var extractedFileURL: URL?
    @State private var loopCount: Int = 1
    @State private var showingPreview = false
    @State private var selectedFormat: AudioLooperManager.AudioFormat = .m4a
    @State private var showingFormatPicker = false
    @State private var showingMusicLibrary = false
    @State private var showingRecording = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Only show top toolbar and header when no audio is loaded
            if audioLooperManager.selectedAudioURL == nil {
                // Top toolbar
                HStack {
                    Text(NSLocalizedString("audio_looper", comment: "App name"))
                        .font(.headline)
                    Spacer()
                    Button(action: {
                        if MFMailComposeViewController.canSendMail() {
                            showingMailComposer = true
                        } else {
                            showingEmailAlert = true
                        }
                    }) {
                        Image(systemName: "headset")
                            .font(.body)
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal)
                
                // Header
                headerView
            }
            
            // Main Content
            if audioLooperManager.isProcessing {
                processingView
            } else if audioLooperManager.selectedAudioURL != nil {
                audioInfoView
            } else {
                audioSelectionView
            }
            
            Spacer()
        }
        .padding()
        .onAppear {
            // Load saved audio files when the view appears
            audioLooperManager.loadSavedAudioFiles()
        }
        .fullScreenCover(isPresented: $showPurchaseView) {
            PurchaseView(isPresented: $showPurchaseView)
                .environmentObject(purchaseModel)
        }
        .sheet(isPresented: $showingMailComposer) {
            MailComposeView()
        }
        .alert("Contact Support", isPresented: $showingEmailAlert) {
            Button("Copy Email") {
                UIPasteboard.general.string = "hi@coolappbox.com"
            }
            Button(NSLocalizedString("ok", comment: "OK button"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("contact_support_message", comment: "Contact support message"))
        }
        .alert(NSLocalizedString("premium_feature", comment: "Premium feature alert title"), isPresented: $showingPaywallAlert) {
            Button(NSLocalizedString("upgrade", comment: "Upgrade button")) {
                showPurchaseView = true
            }
            Button(NSLocalizedString("cancel", comment: "Cancel button"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("premium_subscription_required", comment: "Premium subscription required message"))
        }
        .alert(NSLocalizedString("error", comment: "Error alert title"), isPresented: $showingExtractionResultAlert) {
            Button(NSLocalizedString("ok", comment: "OK button"), role: .cancel) {}
        } message: {
            Text(extractionResultMessage)
        }
        .sheet(isPresented: $showingPreview) {
            if let audioURL = extractedFileURL {
                AudioPreviewSheet(audioURL: audioURL) {
                    showingPreview = false
                }
            }
        }
        .actionSheet(isPresented: $showingFormatPicker) {
            ActionSheet(
                title: Text(NSLocalizedString("select_audio_format", comment: "Select audio format title")),
                message: Text(NSLocalizedString("choose_audio_format_description", comment: "Choose audio format description")),
                buttons: AudioLooperManager.AudioFormat.allCases.map { format in
                    .default(Text("\(format.displayName) - \(format.description)")) {
                        selectedFormat = format
                    }
                } + [.cancel()]
            )
        }
        .sheet(isPresented: $showingMusicLibrary) {
            MusicLibraryView { audioURL in
                audioLooperManager.loadAudio(from: audioURL)
            }
        }
        .sheet(isPresented: $showingRecording) {
            RecordingView { audioURL in
                audioLooperManager.loadAudio(from: audioURL)
            }
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "waveform.badge.plus")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text(NSLocalizedString("loop_audios_custom_count_desc", comment: "App description"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            // Premium button (always show)
            HStack {
                Spacer()
                Button(action: {
                    showPurchaseView = true
                }) {
                    HStack {
                        Image(systemName: purchaseModel.isSubscribed ? "person.crop.circle.badge.checkmark" : "gift.fill")
                            .font(.subheadline)
                        Text(purchaseModel.isSubscribed ? NSLocalizedString("manage_subscription", comment: "") : NSLocalizedString("upgrade_premium", comment: ""))
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(purchaseModel.isSubscribed ? Color.blue : Color.red)
                    .cornerRadius(8)
                }
                Spacer()
            }
            
            if audioLooperManager.selectedAudioURL != nil {
                HStack {
                    Image(systemName: "music.note")
                        .foregroundColor(.green)
                    Text(NSLocalizedString("audio_loaded_successfully", comment: "Audio loaded message"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Audio Selection View
    private var audioSelectionView: some View {
        VStack(spacing: 30) {
            VStack(spacing: 20) {
                Image(systemName: "music.note.house")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                Text(NSLocalizedString("select_audio_file", comment: "Select audio file title"))
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
            }
            
            // Selection options
            VStack(spacing: 16) {
                Button(action: {
                    audioLooperManager.selectAudioFromPhotos()
                }) {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title2)
                        Text(NSLocalizedString("choose_from_library", comment: "Choose from library button"))
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(.blue)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    showingMusicLibrary = true
                }) {
                    HStack {
                        Image(systemName: "music.note.list")
                            .font(.title2)
                        Text(NSLocalizedString("Import from Music Library", comment: "Music library button"))
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(.purple)
                    .padding()
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    showingRecording = true
                }) {
                    HStack {
                        Image(systemName: "mic.fill")
                            .font(.title2)
                        Text(NSLocalizedString("Record Audio", comment: "Record audio button"))
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(.red)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    audioLooperManager.selectAudio()
                }) {
                    HStack {
                        Image(systemName: "folder")
                            .font(.title2)
                        Text(NSLocalizedString("browse_files", comment: "Browse files button"))
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(.green)
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding()
    }
    
    // MARK: - Audio Info View
    private var audioInfoView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(NSLocalizedString("audio_preview", comment: "Audio preview title"))
                    .font(.headline)
                Spacer()
            }
            
            // Audio duration info
            HStack {
                Image(systemName: "timer")
                    .foregroundColor(.blue)
                Text("\(NSLocalizedString("duration", comment: "Duration label")): \(audioLooperManager.formattedTime(audioLooperManager.audioDuration))")
                    .font(.subheadline)
                Spacer()
            }
            
            // Audio Preview with Range Selection
            if let audioURL = audioLooperManager.selectedAudioURL {
                AudioPreviewView(
                    audioURL: audioURL,
                    audioDuration: audioLooperManager.audioDuration,
                    startTime: $audioLooperManager.startTime,
                    endTime: $audioLooperManager.endTime
                )
                .onAppear {
                    // Set the correct time range based on subscription status when audio preview appears
                    audioLooperManager.setInitialTimeRange(isSubscribed: purchaseModel.isSubscribed)
                }
            }
            
            // Selected duration display
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.green)
                Text("\(NSLocalizedString("selected_duration", comment: "Selected duration label")): \(audioLooperManager.formattedTime(audioLooperManager.selectedDuration))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            // Loop count selection
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "repeat")
                        .foregroundColor(.blue)
                    Text(NSLocalizedString("loop_count", comment: "Loop count label"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                }
                
                HStack(spacing: 16) {
                    // Decrease button
                    Button(action: {
                        if loopCount > 1 {
                            loopCount -= 1
                            audioLooperManager.loopCount = loopCount
                        }
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundColor(loopCount > 1 ? .blue : .gray)
                    }
                    .disabled(loopCount <= 1)
                    
                    Spacer()
                    
                    // Current count display
                    VStack(spacing: 4) {
                        Text("\(loopCount)")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Text(NSLocalizedString(loopCount > 1 ? "times" : "time", comment: "Loop count unit"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Increase button
                    Button(action: {
                        let maxAllowed = purchaseModel.isSubscribed ? 50 : 3
                        if loopCount < maxAllowed {
                            loopCount += 1
                            audioLooperManager.loopCount = loopCount
                        } else if !purchaseModel.isSubscribed && loopCount >= 3 {
                            // 免费用户达到3次后，点击加号弹出付费提醒
                            showingPaywallAlert = true
                        }
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(loopCount < (purchaseModel.isSubscribed ? 50 : 50) ? .blue : .gray)
                    }
                    .disabled(purchaseModel.isSubscribed && loopCount >= 50)
                }
                
                if !purchaseModel.isSubscribed {
                    Text(NSLocalizedString("free_users_limited_3_loops_max", comment: "Free user loop limit message"))
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color(.systemGray6))
            .cornerRadius(8)
            
            // Audio format selection
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "waveform")
                        .foregroundColor(.blue)
                    Text(NSLocalizedString("output_format", comment: "Output format label"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                }
                
                Button(action: {
                    showingFormatPicker = true
                }) {
                    HStack {
                        Text(selectedFormat.displayName)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text(selectedFormat.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                        
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color(.systemGray6))
            .cornerRadius(8)
            
            // Free user limitation warning
            if !purchaseModel.isSubscribed && audioLooperManager.loopCount > 3 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(NSLocalizedString("free_users_limited_3_loops", comment: "Free user upgrade message"))
                        .font(.caption)
                        .foregroundColor(.orange)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            
            // Action buttons
            HStack(spacing: 16) {
                // Clear button
                Button(action: {
                    audioLooperManager.selectedAudioURL = nil
                    audioLooperManager.audioDuration = 0
                    audioLooperManager.startTime = 0
                    audioLooperManager.endTime = 0
                    extractedFileURL = nil
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text(NSLocalizedString("clear", comment: "Clear button"))
                    }
                    .foregroundColor(.red)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
                
                // Generate Audio button
                Button(action: {
                    checkAndStartLoop()
                }) {
                    HStack {
                        Image(systemName: "waveform.badge.plus")
                        Text(NSLocalizedString("generate_audio", comment: "Generate audio button"))
                    }
                    .foregroundColor(.white)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Processing View
    private var processingView: some View {
        VStack(spacing: 20) {
            ProgressView(value: audioLooperManager.progress)
                .progressViewStyle(LinearProgressViewStyle())
            
            Text(audioLooperManager.currentTask)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Text("\(Int(audioLooperManager.progress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button(NSLocalizedString("cancel", comment: "Cancel button")) {
                audioLooperManager.cancelExport()
                audioLooperManager.selectedAudioURL = nil
                audioLooperManager.audioDuration = 0
                audioLooperManager.startTime = 0
                audioLooperManager.endTime = 0
                extractedFileURL = nil
            }
            .foregroundColor(.red)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.red.opacity(0.1))
            .cornerRadius(8)
        }
        .padding()
    }
    
    
    // MARK: - Private Methods
    
    private func checkAndStartLoop() {
        // Sync loop count from UI to manager
        audioLooperManager.loopCount = loopCount
        
        // Check free user limits
        if !purchaseModel.isSubscribed && loopCount > 3 {
            showingPaywallAlert = true
            return
        }
        
        // 确保所有alert都关闭后再开始循环
        showingExtractionResultAlert = false
        showingEmailAlert = false
        showingPaywallAlert = false
        
        // 延迟一下确保alert完全消失，然后直接开始循环
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            startLoop()
        }
    }
    
    private func startLoop() {
        // Enforce loop limit for free users
        if !purchaseModel.isSubscribed && loopCount > 3 {
            loopCount = 3
            audioLooperManager.loopCount = 3
        }
        
        audioLooperManager.loopAudio(format: selectedFormat) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let url):
                    self.extractedFileURL = url
                    // 显示预览界面
                    self.showingPreview = true
                case .failure(let error):
                    self.extractionResultMessage = "Audio loop creation failed: \(error.localizedDescription)"
                    self.showingExtractionResultAlert = true
                }
            }
        }
    }
    
    private func shareAudioFile(url: URL) {
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        
        // Configure popover for iPad
        PopoverHelper.configurePopover(activityVC.popoverPresentationController)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(activityVC, animated: true)
        }
    }
    
    private func formatFileDate(_ url: URL) -> String {
        guard let creationDate = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) else {
            return "Unknown date"
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: creationDate)
    }
}


#Preview {
    AudioLooperView()
        .environmentObject(PurchaseModel())
} 

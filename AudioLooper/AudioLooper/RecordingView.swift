import SwiftUI
import AVFoundation

struct RecordingView: View {
    @StateObject private var recorder = AudioRecorder()
    @Environment(\.dismiss) var dismiss
    let onAudioRecorded: (URL) -> Void
    
    @State private var showingPermissionAlert = false
    @State private var showingPreview = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                if !recorder.hasPermission {
                    permissionView
                } else {
                    recordingInterface
                }
            }
            .padding()
            .navigationTitle(NSLocalizedString("record_audio", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("cancel", comment: "")) {
                        if recorder.isRecording {
                            recorder.stopRecording()
                        }
                        dismiss()
                    }
                }
                
                if let recordingURL = recorder.recordingURL, !recorder.isRecording {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(NSLocalizedString("use_recording", comment: "")) {
                            onAudioRecorded(recordingURL)
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $showingPreview) {
                if let url = recorder.recordingURL {
                    AudioPreviewSheet(audioURL: url) {
                        showingPreview = false
                    }
                }
            }
            .alert(NSLocalizedString("microphone_access_required", comment: ""), isPresented: $showingPermissionAlert) {
                Button(NSLocalizedString("settings", comment: "")) {
                    if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsUrl)
                    }
                }
                Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("microphone_settings_message", comment: ""))
            }
        }
    }
    
    private var permissionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.circle")
                .font(.system(size: 80))
                .foregroundColor(.red)
            
            Text(NSLocalizedString("microphone_access_required", comment: ""))
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(NSLocalizedString("microphone_permission_message", comment: ""))
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            Button(NSLocalizedString("request_access", comment: "")) {
                recorder.checkPermission()
                if !recorder.hasPermission {
                    showingPermissionAlert = true
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    private var recordingInterface: some View {
        VStack(spacing: 40) {
            // Recording visualization
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.1))
                        .frame(width: 200, height: 200)
                    
                    Circle()
                        .fill(Color.red.opacity(0.3))
                        .frame(width: 160, height: 160)
                        .scaleEffect(recorder.isRecording ? 1.0 + CGFloat(recorder.audioLevel) * 0.3 : 1.0)
                        .animation(.easeInOut(duration: 0.1), value: recorder.audioLevel)
                    
                    Circle()
                        .fill(Color.red)
                        .frame(width: 120, height: 120)
                        .scaleEffect(recorder.isRecording ? 1.0 + CGFloat(recorder.audioLevel) * 0.2 : 1.0)
                        .animation(.easeInOut(duration: 0.1), value: recorder.audioLevel)
                    
                    Image(systemName: recorder.isRecording ? "mic.fill" : "mic")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                }
                
                // Audio level indicator
                if recorder.isRecording {
                    VStack(spacing: 8) {
                        HStack(spacing: 4) {
                            ForEach(0..<20, id: \.self) { index in
                                Rectangle()
                                    .fill(index < Int(CGFloat(recorder.audioLevel) * 20) ? Color.green : Color.gray.opacity(0.3))
                                    .frame(width: 6, height: CGFloat(8 + index * 2))
                                    .animation(.easeInOut(duration: 0.1), value: recorder.audioLevel)
                            }
                        }
                        
                        Text(NSLocalizedString("recording", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Duration display
            VStack(spacing: 8) {
                Text(recorder.formatRecordingTime(recorder.recordingDuration))
                    .font(.system(size: 36, weight: .light, design: .monospaced))
                    .foregroundColor(recorder.isRecording ? .red : .primary)
                
                if !recorder.isRecording && recorder.recordingURL != nil {
                    Text(NSLocalizedString("recording_completed", comment: ""))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            // Control buttons
            HStack(spacing: 40) {
                if recorder.recordingURL != nil && !recorder.isRecording {
                    // Preview button
                    Button(action: {
                        showingPreview = true
                    }) {
                        VStack(spacing: 8) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 40))
                            Text(NSLocalizedString("preview", comment: ""))
                                .font(.caption)
                        }
                        .foregroundColor(.blue)
                    }
                }
                
                // Main record button
                Button(action: {
                    if recorder.isRecording {
                        recorder.stopRecording()
                    } else {
                        recorder.startRecording()
                    }
                }) {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(recorder.isRecording ? Color.red : Color.gray.opacity(0.2))
                                .frame(width: 80, height: 80)
                            
                            if recorder.isRecording {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white)
                                    .frame(width: 30, height: 30)
                            } else {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(recorder.recordingURL != nil ? .gray : .red)
                            }
                        }
                        
                        Text(recorder.isRecording ? 
                             NSLocalizedString("stop", comment: "") : 
                             NSLocalizedString("record", comment: ""))
                            .font(.caption)
                            .foregroundColor(recorder.isRecording ? .red : .primary)
                    }
                }
                .disabled(!recorder.hasPermission)
                
                if recorder.recordingURL != nil && !recorder.isRecording {
                    // Delete button
                    Button(action: {
                        if let url = recorder.recordingURL {
                            try? FileManager.default.removeItem(at: url)
                        }
                        recorder.recordingURL = nil
                        recorder.recordingDuration = 0
                    }) {
                        VStack(spacing: 8) {
                            Image(systemName: "trash.circle.fill")
                                .font(.system(size: 40))
                            Text(NSLocalizedString("delete", comment: ""))
                                .font(.caption)
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            
            Spacer()
            
            // Instructions
            if recorder.recordingURL == nil {
                VStack(spacing: 8) {
                    Text(NSLocalizedString("tap_record_instruction", comment: ""))
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Text(NSLocalizedString("recording_limit_instruction", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

#Preview {
    RecordingView { url in
        print("Audio recorded: \(url)")
    }
}
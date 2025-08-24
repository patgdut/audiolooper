import SwiftUI
import AVFoundation

class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0.0
    @Published var recordingURL: URL?
    @Published var hasPermission = false
    
    private var audioRecorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private var durationTimer: Timer?
    
    override init() {
        super.init()
        checkPermission()
    }
    
    func checkPermission() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            hasPermission = true
        case .denied:
            hasPermission = false
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] allowed in
                DispatchQueue.main.async {
                    self?.hasPermission = allowed
                }
            }
        @unknown default:
            hasPermission = false
        }
    }
    
    func startRecording() {
        guard hasPermission else {
            checkPermission()
            return
        }
        
        guard !isRecording else { return }
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioURL = documentsPath.appendingPathComponent("recording_\(Date().timeIntervalSince1970).m4a")
        
        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            audioRecorder = try AVAudioRecorder(url: audioURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            
            recordingURL = audioURL
            isRecording = true
            recordingDuration = 0
            
            startLevelMonitoring()
            startDurationTimer()
            
        } catch {
            print("Failed to start recording: \(error.localizedDescription)")
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        audioRecorder?.stop()
        stopLevelMonitoring()
        stopDurationTimer()
        
        isRecording = false
        audioLevel = 0.0
        
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
    }
    
    func pauseRecording() {
        audioRecorder?.pause()
        stopLevelMonitoring()
        stopDurationTimer()
        isRecording = false
    }
    
    func resumeRecording() {
        audioRecorder?.record()
        startLevelMonitoring()
        startDurationTimer()
        isRecording = true
    }
    
    private func startLevelMonitoring() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let recorder = self.audioRecorder else { return }
            
            recorder.updateMeters()
            let averagePower = recorder.averagePower(forChannel: 0)
            let normalizedLevel = self.normalizedPowerLevel(from: averagePower)
            
            DispatchQueue.main.async {
                self.audioLevel = normalizedLevel
            }
        }
    }
    
    private func stopLevelMonitoring() {
        levelTimer?.invalidate()
        levelTimer = nil
    }
    
    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let recorder = self.audioRecorder else { return }
            
            DispatchQueue.main.async {
                self.recordingDuration = recorder.currentTime
            }
        }
    }
    
    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
    
    private func normalizedPowerLevel(from power: Float) -> Float {
        // Convert decibel value to linear scale (0.0 to 1.0)
        let minDb: Float = -80.0
        
        if power < minDb {
            return 0.0
        } else if power >= 1.0 {
            return 1.0
        } else {
            return (abs(minDb) - abs(power)) / abs(minDb)
        }
    }
    
    func formatRecordingTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, milliseconds)
    }
    
    // MARK: - AVAudioRecorderDelegate
    
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("Recording failed")
            recordingURL = nil
        }
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            print("Recording encode error: \(error.localizedDescription)")
        }
        recordingURL = nil
    }
}
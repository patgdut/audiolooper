import SwiftUI
import AVKit
import AVFoundation

struct AudioPreviewSheet: View {
    let audioURL: URL
    let onDismiss: () -> Void
    
    @State private var player: AVPlayer?
    @State private var showingShareSheet = false
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Title
                Text(NSLocalizedString("audio_preview_title", comment: "Audio preview title"))
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.top)
                
                // Audio visualization
                VStack(spacing: 20) {
                    // Large audio icon with waveform effect
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [.blue.opacity(0.3), .blue.opacity(0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            .frame(width: 200, height: 200)
                        
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 100))
                            .foregroundColor(.blue)
                            .scaleEffect(isPlaying ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isPlaying)
                    }
                    
                    // Progress bar
                    VStack(spacing: 8) {
                        ProgressView(value: duration > 0 ? currentTime / duration : 0)
                            .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        
                        HStack {
                            Text(formattedTime(currentTime))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(formattedTime(duration))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 40)
                }
                .padding(.horizontal)
                
                // Action Buttons
                HStack(spacing: 20) {
                    // Play/Pause Button
                    Button(action: {
                        togglePlayPause()
                    }) {
                        HStack {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.title2)
                            Text(isPlaying ? NSLocalizedString("pause_audio", comment: "Pause audio button") : NSLocalizedString("play_audio", comment: "Play audio button"))
                        }
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                    
                    // Share Button
                    Button(action: {
                        showingShareSheet = true
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title2)
                            Text(NSLocalizedString("share_audio", comment: "Share audio button"))
                        }
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green)
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button(NSLocalizedString("done", comment: "Done button")) {
                    onDismiss()
                }
            )
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
            isPlaying = false
        }
        .sheet(isPresented: $showingShareSheet) {
            if let player = player {
                player.pause()
                isPlaying = false
            }
        } content: {
            ActivityViewController(activityItems: [audioURL])
        }
    }
    
    private func setupPlayer() {
        let playerItem = AVPlayerItem(url: audioURL)
        player = AVPlayer(playerItem: playerItem)
        
        // Get duration
        if let asset = playerItem.asset as? AVURLAsset {
            Task {
                do {
                    let duration = try await asset.load(.duration)
                    DispatchQueue.main.async {
                        self.duration = CMTimeGetSeconds(duration)
                    }
                } catch {
                    print("Failed to load audio duration: \(error)")
                }
            }
        }
        
        // Add time observer
        let timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { time in
            currentTime = CMTimeGetSeconds(time)
        }
        
        // Setup looping
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            player?.seek(to: .zero)
            if isPlaying {
                player?.play()
            }
        }
    }
    
    private func togglePlayPause() {
        guard let player = player else { return }
        
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }
    
    private func formattedTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}


#Preview {
    AudioPreviewSheet(audioURL: URL(fileURLWithPath: "/tmp/test.m4a")) {
        // Preview dismiss action
    }
}
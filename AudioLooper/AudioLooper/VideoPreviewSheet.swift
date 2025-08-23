import SwiftUI
import AVKit
import AVFoundation

struct VideoPreviewSheet: View {
    let videoURL: URL
    let onDismiss: () -> Void
    
    @State private var player: AVPlayer?
    @State private var showingShareSheet = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Title
                Text(NSLocalizedString("video_preview_title", comment: "Video preview title"))
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.top)
                
                // Video Player
                if let player = player {
                    VideoPlayer(player: player)
                        .aspectRatio(16/9, contentMode: .fit)
                        .cornerRadius(12)
                        .padding(.horizontal)
                } else {
                    Rectangle()
                        .fill(Color.black)
                        .aspectRatio(16/9, contentMode: .fit)
                        .cornerRadius(12)
                        .padding(.horizontal)
                        .overlay(
                            ProgressView()
                                .scaleEffect(1.5)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        )
                }
                
                // Action Buttons
                HStack(spacing: 20) {
                    // Play/Pause Button
                    Button(action: {
                        if let player = player {
                            if player.rate == 0 {
                                player.play()
                            } else {
                                player.pause()
                            }
                        }
                    }) {
                        HStack {
                            Image(systemName: "play.circle.fill")
                                .font(.title2)
                            Text(NSLocalizedString("play_video", comment: "Play video button"))
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
                            Text(NSLocalizedString("share_video", comment: "Share video button"))
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
        }
        .sheet(isPresented: $showingShareSheet) {
            if let player = player {
                player.pause()
            }
        } content: {
            ActivityViewController(activityItems: [videoURL])
        }
    }
    
    private func setupPlayer() {
        let playerItem = AVPlayerItem(url: videoURL)
        player = AVPlayer(playerItem: playerItem)
        
        // Setup looping
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            player?.seek(to: .zero)
            player?.play()
        }
    }
}


#Preview {
    VideoPreviewSheet(videoURL: URL(fileURLWithPath: "/tmp/test.mp4")) {
        // Preview dismiss action
    }
}
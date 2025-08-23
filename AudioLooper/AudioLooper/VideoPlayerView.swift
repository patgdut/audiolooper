import SwiftUI
import AVFoundation
import UIKit

struct VideoPlayerView: UIViewRepresentable {
    let url: URL
    @Binding var currentTime: TimeInterval
    @Binding var isPlaying: Bool
    @Binding var seekToTime: TimeInterval?
    let startTime: TimeInterval
    let endTime: TimeInterval
    
    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        
        let player = AVPlayer(url: url)
        let playerLayer = AVPlayerLayer(player: player)
        
        playerLayer.videoGravity = .resizeAspect
        containerView.layer.addSublayer(playerLayer)
        
        // Store player in coordinator
        context.coordinator.player = player
        context.coordinator.playerLayer = playerLayer
        context.coordinator.startTime = startTime
        context.coordinator.endTime = endTime
        
        // Wait for the player item to be ready, then seek to first frame
        let playerItem = player.currentItem
        if let item = playerItem {
            // Add observer for when the item is ready to play
            let observer = item.observe(\.status, options: [.new]) { item, _ in
                if item.status == .readyToPlay {
                    DispatchQueue.main.async {
                        let initialTime = CMTime(seconds: context.coordinator.startTime, preferredTimescale: 600)
                        player.seek(to: initialTime, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                            if finished {
                                // Check player status before calling preroll
                                if player.status == .readyToPlay {
                                    player.preroll(atRate: 0.0) { success in
                                        if success {
                                            // Update current time binding
                                            currentTime = context.coordinator.startTime
                                            // Ensure the layer shows the frame
                                            context.coordinator.playerLayer?.setNeedsDisplay()
                                        }
                                    }
                                } else {
                                    // Just update the current time without preroll
                                    currentTime = context.coordinator.startTime
                                }
                            }
                        }
                    }
                }
            }
            context.coordinator.statusObserver = observer
        } else {
            // Fallback: seek immediately but check status first
            let initialTime = CMTime(seconds: startTime, preferredTimescale: 600)
            player.seek(to: initialTime, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                if finished {
                    // Only call preroll if player is ready
                    if player.status == .readyToPlay {
                        player.preroll(atRate: 0.0) { success in
                            if success {
                                currentTime = startTime
                                context.coordinator.playerLayer?.setNeedsDisplay()
                            }
                        }
                    } else {
                        // Just update current time
                        currentTime = startTime
                    }
                }
            }
        }
        
        // Add time observer
        let timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { time in
            let currentSeconds = CMTimeGetSeconds(time)
            DispatchQueue.main.async {
                currentTime = currentSeconds
                
                // Auto-pause when reaching end time
                if currentSeconds >= context.coordinator.endTime && context.coordinator.isPlayingRange {
                    context.coordinator.player?.pause()
                    isPlaying = false
                    context.coordinator.isPlayingRange = false
                }
            }
        }
        context.coordinator.timeObserver = timeObserver
        
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update player layer frame
        if let playerLayer = context.coordinator.playerLayer {
            playerLayer.frame = uiView.bounds
        }
        
        // Update time range in coordinator
        context.coordinator.startTime = startTime
        context.coordinator.endTime = endTime
        
        // Handle seek requests
        if let seekTime = seekToTime {
            context.coordinator.seek(to: seekTime)
            DispatchQueue.main.async {
                self.seekToTime = nil // Clear the seek request
            }
        }
        
        // Handle play/pause
        if isPlaying && !context.coordinator.isPlayingRange {
            // When starting to play, ensure we're within the selected range
            if currentTime < startTime || currentTime >= endTime {
                context.coordinator.seek(to: startTime)
            }
            context.coordinator.isPlayingRange = true
            context.coordinator.player?.play()
        } else if !isPlaying {
            context.coordinator.isPlayingRange = false
            context.coordinator.player?.pause()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var player: AVPlayer?
        var playerLayer: AVPlayerLayer?
        var timeObserver: Any?
        var statusObserver: NSKeyValueObservation?
        var startTime: TimeInterval = 0
        var endTime: TimeInterval = 0
        var isPlayingRange: Bool = false
        
        deinit {
            if let timeObserver = timeObserver {
                player?.removeTimeObserver(timeObserver)
            }
            statusObserver?.invalidate()
        }
        
        func seek(to time: TimeInterval) {
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)
            player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                if finished {
                    // Only call preroll if player is ready
                    if self.player?.status == .readyToPlay {
                        self.player?.preroll(atRate: 0.0) { success in
                            if success {
                                self.playerLayer?.setNeedsDisplay()
                            }
                        }
                    } else {
                        // Just refresh the layer without preroll
                        self.playerLayer?.setNeedsDisplay()
                    }
                }
            }
        }
    }
}

struct VideoPreviewView: View {
    let videoURL: URL
    let videoDuration: TimeInterval
    @Binding var startTime: TimeInterval
    @Binding var endTime: TimeInterval
    
    @State private var currentTime: TimeInterval = 0
    @State private var isPlaying = false
    @State private var seekToTimeValue: TimeInterval? = nil
    
    var body: some View {
        VStack(spacing: 16) {
            // Video Player
            VideoPlayerView(
                url: videoURL,
                currentTime: $currentTime,
                isPlaying: $isPlaying,
                seekToTime: $seekToTimeValue,
                startTime: startTime,
                endTime: endTime
            )
            .frame(height: 200)
            .background(Color.black)
            .cornerRadius(12)
            .clipped()
            .onAppear {
                // Initialize current time to start time when view appears
                currentTime = startTime
            }
            .onChange(of: startTime) { _, newStartTime in
                // When start time changes, update current time if not playing
                if !isPlaying {
                    currentTime = newStartTime
                    seekToTime(newStartTime)
                }
            }
            .onChange(of: endTime) { _, _ in
                // When end time changes, ensure current time is within range
                if currentTime >= endTime && !isPlaying {
                    currentTime = startTime
                    seekToTime(startTime)
                }
            }
            
            // Play Controls
            HStack(spacing: 20) {
                Button(action: {
                    if isPlaying {
                        isPlaying = false
                    } else {
                        // Ensure we start from the correct position
                        if currentTime < startTime || currentTime >= endTime {
                            currentTime = startTime
                            seekToTime(startTime)
                        }
                        isPlaying = true
                    }
                }) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title)
                        .foregroundColor(.blue)
                }
                
                Button(action: {
                    seekToStart()
                }) {
                    HStack {
                        Image(systemName: "gobackward")
                        Text(NSLocalizedString("start", comment: "Start button"))
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                
                Button(action: {
                    seekToEnd()
                }) {
                    HStack {
                        Text(NSLocalizedString("end", comment: "End button"))
                        Image(systemName: "goforward")
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
            
            // Time Range Selector
            VideoTimeRangeSelector(
                duration: videoDuration,
                startTime: $startTime,
                endTime: $endTime,
                currentTime: currentTime,
                onTimeSeek: { time in
                    seekToTime(time)
                }
            )
        }
        .onDisappear {
            isPlaying = false
        }
    }
    
    private func seekToStart() {
        isPlaying = false
        currentTime = startTime
        seekToTime(startTime)
    }
    
    private func seekToEnd() {
        isPlaying = false
        currentTime = max(startTime, endTime - 0.5) // Seek slightly before end
        seekToTime(currentTime)
    }
    
    private func seekToTime(_ time: TimeInterval) {
        seekToTimeValue = time
    }
}

struct VideoTimeRangeSelector: View {
    let duration: TimeInterval
    @Binding var startTime: TimeInterval
    @Binding var endTime: TimeInterval
    let currentTime: TimeInterval
    let onTimeSeek: ((TimeInterval) -> Void)?
    
    @State private var isDraggingStart = false
    @State private var isDraggingEnd = false
    
    private let trackHeight: CGFloat = 4
    private let thumbSize: CGFloat = 20
    private let selectedHeight: CGFloat = 8
    
    init(duration: TimeInterval, startTime: Binding<TimeInterval>, endTime: Binding<TimeInterval>, currentTime: TimeInterval, onTimeSeek: ((TimeInterval) -> Void)? = nil) {
        self.duration = duration
        self._startTime = startTime
        self._endTime = endTime
        self.currentTime = currentTime
        self.onTimeSeek = onTimeSeek
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Time labels
            HStack {
                Text(NSLocalizedString("select_time_range", comment: "Time range selector title"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(formattedTime(endTime - startTime))")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            
            // Visual time range selector
            GeometryReader { geometry in
                let width = geometry.size.width
                let startPosition = CGFloat(startTime / duration) * width
                let endPosition = CGFloat(endTime / duration) * width
                let currentPosition = CGFloat(currentTime / duration) * width
                
                ZStack(alignment: .leading) {
                    // Background track (tappable for seeking)
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: trackHeight)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            let tapTime = Double(location.x / width) * duration
                            let clampedTime = max(0, min(tapTime, duration))
                            onTimeSeek?(clampedTime)
                        }
                    
                    // Selected range
                    Rectangle()
                        .fill(Color.blue.opacity(0.6))
                        .frame(width: max(0, endPosition - startPosition), height: selectedHeight)
                        .offset(x: startPosition)
                    
                    // Current time indicator
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: 2, height: selectedHeight + 4)
                        .offset(x: currentPosition - 1)
                    
                    // Start thumb
                    Circle()
                        .fill(Color.blue)
                        .frame(width: thumbSize, height: thumbSize)
                        .offset(x: startPosition - thumbSize/2)
                        .shadow(radius: 2)
                        .scaleEffect(isDraggingStart ? 1.2 : 1.0)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    isDraggingStart = true
                                    let newPosition = max(0, min(value.location.x, endPosition - thumbSize))
                                    let newTime = Double(newPosition / width) * duration
                                    startTime = min(newTime, endTime - 1)
                                }
                                .onEnded { _ in
                                    isDraggingStart = false
                                }
                        )
                    
                    // End thumb
                    Circle()
                        .fill(Color.blue)
                        .frame(width: thumbSize, height: thumbSize)
                        .offset(x: endPosition - thumbSize/2)
                        .shadow(radius: 2)
                        .scaleEffect(isDraggingEnd ? 1.2 : 1.0)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    isDraggingEnd = true
                                    let newPosition = max(startPosition + thumbSize, min(value.location.x, width))
                                    let newTime = Double(newPosition / width) * duration
                                    endTime = max(startTime + 1, min(newTime, duration))
                                }
                                .onEnded { _ in
                                    isDraggingEnd = false
                                }
                        )
                }
            }
            .frame(height: max(trackHeight, selectedHeight, thumbSize) + 4)
            
            // Time indicators
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("start_time", comment: "Start time label"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(formattedTime(startTime))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                VStack(spacing: 2) {
                    Text(NSLocalizedString("current_time", comment: "Current time label"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(formattedTime(currentTime))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(NSLocalizedString("end_time", comment: "End time label"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(formattedTime(endTime))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private func formattedTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    VStack {
        Text(NSLocalizedString("video_preview_component", comment: "Video preview component placeholder"))
        Text(NSLocalizedString("need_video_url_preview", comment: "Need video URL for preview"))
    }
}
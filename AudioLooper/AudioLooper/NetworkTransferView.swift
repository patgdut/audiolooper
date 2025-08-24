import SwiftUI
import Network

struct NetworkTransferView: View {
    @StateObject private var networkManager = NetworkTransferManager()
    @Environment(\.dismiss) var dismiss
    let onAudioReceived: (URL) -> Void
    
    @State private var showingInfoAlert = false
    @State private var showingReceiveAnimation = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                if networkManager.isServerRunning {
                    serverRunningView
                } else {
                    serverStoppedView
                }
            }
            .padding()
            .navigationTitle(NSLocalizedString("network_transfer", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("cancel", comment: "")) {
                        networkManager.stopServer()
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("info", comment: "")) {
                        showingInfoAlert = true
                    }
                }
            }
            .onAppear {
                if !networkManager.isServerRunning {
                    networkManager.startServer()
                }
            }
            .onDisappear {
                networkManager.stopServer()
            }
            .alert(NSLocalizedString("network_transfer_info_title", comment: ""), isPresented: $showingInfoAlert) {
                Button(NSLocalizedString("ok", comment: ""), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("network_transfer_info_message", comment: ""))
            }
            .alert(NSLocalizedString("error", comment: ""), isPresented: $networkManager.showError) {
                Button(NSLocalizedString("ok", comment: ""), role: .cancel) {}
            } message: {
                Text(networkManager.errorMessage)
            }
            .onChange(of: networkManager.receivedFileURL) { url in
                if let url = url {
                    onAudioReceived(url)
                    dismiss()
                }
            }
        }
    }
    
    private var serverStoppedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 80))
                .foregroundColor(.gray)
            
            Text(NSLocalizedString("network_server_stopped", comment: ""))
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
            
            Text(NSLocalizedString("network_starting_server", comment: ""))
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            ProgressView()
                .scaleEffect(1.2)
        }
    }
    
    private var serverRunningView: some View {
        VStack(spacing: 30) {
            // Server status
            VStack(spacing: 15) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.2))
                        .frame(width: 120, height: 120)
                    
                    Circle()
                        .fill(Color.green.opacity(0.4))
                        .frame(width: 80, height: 80)
                        .scaleEffect(showingReceiveAnimation ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: showingReceiveAnimation)
                    
                    Image(systemName: "wifi")
                        .font(.system(size: 40))
                        .foregroundColor(.green)
                }
                
                VStack(spacing: 4) {
                    Text(NSLocalizedString("network_server_running", comment: ""))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                    
                    Text(NSLocalizedString("network_ready_receive", comment: ""))
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            
            // Connection info
            VStack(spacing: 20) {
                connectionInfoCard(
                    icon: "network",
                    title: NSLocalizedString("network_local_ip", comment: ""),
                    value: networkManager.serverIP.isEmpty ? NSLocalizedString("network_detecting", comment: "") : networkManager.serverIP
                )
                
                connectionInfoCard(
                    icon: "number",
                    title: NSLocalizedString("network_port", comment: ""),
                    value: String(networkManager.serverPort)
                )
                
                connectionInfoCard(
                    icon: "link",
                    title: NSLocalizedString("network_web_address", comment: ""),
                    value: networkManager.serverIP.isEmpty ? NSLocalizedString("network_detecting", comment: "") : "http://\(networkManager.serverIP):\(networkManager.serverPort)"
                )
            }
            
            // Connected devices
            if !networkManager.connectedDevices.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(NSLocalizedString("network_connected_devices", comment: ""))
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    ForEach(networkManager.connectedDevices, id: \.self) { device in
                        HStack {
                            Image(systemName: "desktopcomputer")
                                .foregroundColor(.blue)
                            Text(device)
                                .font(.body)
                                .foregroundColor(.secondary)
                            Spacer()
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                }
            }
            
            // Transfer progress
            if networkManager.isReceivingFile {
                VStack(spacing: 12) {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(NSLocalizedString("network_receiving_file", comment: ""))
                            .font(.body)
                            .foregroundColor(.blue)
                    }
                    
                    ProgressView(value: networkManager.transferProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                }
            }
            
            Spacer()
            
            // Instructions
            VStack(spacing: 16) {
                Text(NSLocalizedString("network_transfer_instructions", comment: ""))
                    .font(.headline)
                    .multilineTextAlignment(.center)
                
                VStack(alignment: .leading, spacing: 8) {
                    instructionStep(
                        number: 1,
                        text: NSLocalizedString("network_instruction_step1", comment: "")
                    )
                    instructionStep(
                        number: 2,
                        text: NSLocalizedString("network_instruction_step2", comment: "")
                    )
                    instructionStep(
                        number: 3,
                        text: NSLocalizedString("network_instruction_step3", comment: "")
                    )
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .onAppear {
            showingReceiveAnimation = true
        }
        .onDisappear {
            showingReceiveAnimation = false
        }
    }
    
    private func connectionInfoCard(icon: String, title: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.body)
                    .fontWeight(.medium)
                    .textSelection(.enabled)
            }
            
            Spacer()
            
            if !value.isEmpty && value != NSLocalizedString("network_detecting", comment: "") {
                Button(action: {
                    UIPasteboard.general.string = value
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
    
    private func instructionStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.blue))
            
            Text(text)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
    }
}

#Preview {
    NetworkTransferView { url in
        print("Audio received: \(url)")
    }
}
import Foundation
import Network
import AVFoundation
import UIKit

enum NetworkTransferError: Error {
    case serverStartFailed
    case invalidFileData
    case unsupportedFileType
    case networkUnavailable
    case fileWriteFailed
    
    var localizedDescription: String {
        switch self {
        case .serverStartFailed:
            return NSLocalizedString("network_server_start_failed", comment: "")
        case .invalidFileData:
            return NSLocalizedString("network_invalid_file_data", comment: "")
        case .unsupportedFileType:
            return NSLocalizedString("network_unsupported_file_type", comment: "")
        case .networkUnavailable:
            return NSLocalizedString("network_unavailable", comment: "")
        case .fileWriteFailed:
            return NSLocalizedString("network_file_write_failed", comment: "")
        }
    }
}

class NetworkTransferManager: NSObject, ObservableObject {
    @Published var isServerRunning = false
    @Published var serverPort: UInt16 = 8080
    @Published var serverIP: String = ""
    @Published var connectedDevices: [String] = []
    @Published var transferProgress: Double = 0.0
    @Published var isReceivingFile = false
    @Published var receivedFileURL: URL?
    @Published var errorMessage: String = ""
    @Published var showError = false
    
    private var listener: NWListener?
    private var netService: NetService?
    private let supportedAudioExtensions = ["mp3", "m4a", "wav", "aac", "flac", "aiff"]
    
    override init() {
        super.init()
        setupListener()
    }
    
    deinit {
        stopServer()
    }
    
    // MARK: - Server Management
    
    func startServer() {
        guard !isServerRunning else { return }
        
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.includePeerToPeer = true
            
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: serverPort) ?? .any)
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            
            listener?.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isServerRunning = true
                        if let port = self?.listener?.port {
                            self?.serverPort = port.rawValue
                        }
                        self?.getLocalIPAddress()
                        self?.startBonjourService()
                    case .failed(let error):
                        print("Server failed: \(error)")
                        self?.isServerRunning = false
                        self?.showError(NSLocalizedString("network_server_start_failed", comment: ""))
                    case .cancelled:
                        self?.isServerRunning = false
                    default:
                        break
                    }
                }
            }
            
            listener?.start(queue: .global(qos: .userInitiated))
            
        } catch {
            print("Failed to start server: \(error)")
            showError(error.localizedDescription)
        }
    }
    
    func stopServer() {
        listener?.cancel()
        listener = nil
        netService?.stop()
        netService = nil
        
        DispatchQueue.main.async {
            self.isServerRunning = false
            self.connectedDevices.removeAll()
        }
    }
    
    private func setupListener() {
        // Setup will be done when starting server
    }
    
    // MARK: - Bonjour Service
    
    private func startBonjourService() {
        netService = NetService(domain: "", type: "_audiolooper._tcp.", name: "AudioLooper", port: Int32(serverPort))
        netService?.delegate = self
        netService?.publish()
    }
    
    // MARK: - Connection Handling
    
    private func handleNewConnection(_ connection: NWConnection) {
        print("New connection from: \(connection.endpoint)")
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                DispatchQueue.main.async {
                    if let endpoint = connection.endpoint.debugDescription.components(separatedBy: ":").first {
                        if let strongSelf = self, !strongSelf.connectedDevices.contains(endpoint) {
                            strongSelf.connectedDevices.append(endpoint)
                        }
                    }
                }
                self?.receiveHTTPRequest(connection)
            case .failed(_), .cancelled:
                DispatchQueue.main.async {
                    if let endpoint = connection.endpoint.debugDescription.components(separatedBy: ":").first {
                        self?.connectedDevices.removeAll { $0 == endpoint }
                    }
                }
            default:
                break
            }
        }
        
        connection.start(queue: .global(qos: .userInitiated))
    }
    
    // MARK: - HTTP Request Handling
    
    private func receiveHTTPRequest(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                let request = String(data: data, encoding: .utf8) ?? ""
                self?.processHTTPRequest(request, connection: connection)
            }
            
            if !isComplete {
                self?.receiveHTTPRequest(connection)
            }
        }
    }
    
    private func processHTTPRequest(_ request: String, connection: NWConnection) {
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return }
        
        let components = firstLine.components(separatedBy: " ")
        guard components.count >= 2 else { return }
        
        let method = components[0]
        let path = components[1]
        
        if method == "GET" && path == "/" {
            sendWebPage(to: connection)
        } else if method == "POST" && path == "/upload" {
            handleFileUpload(request, connection: connection)
        } else {
            send404Response(to: connection)
        }
    }
    
    private func sendWebPage(to connection: NWConnection) {
        let html = createUploadWebPage()
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(html.utf8.count)\r
        Connection: close\r
        \r
        \(html)
        """
        
        let responseData = response.data(using: .utf8)!
        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private func createUploadWebPage() -> String {
        // Detect system language
        let language = getCurrentLanguage()
        
        switch language {
        case "zh-Hans", "zh-CN":
            return createChineseSimplifiedHTML()
        case "zh-Hant", "zh-TW", "zh-HK":
            return createChineseTraditionalHTML()
        default:
            return createEnglishHTML()
        }
    }
    
    private func getCurrentLanguage() -> String {
        if let language = Locale.current.language.languageCode?.identifier {
            if let region = Locale.current.language.region?.identifier {
                return "\(language)-\(region)"
            }
            return language
        }
        return "en"
    }
    
    private func createEnglishHTML() -> String {
        return createHTMLTemplate(
            title: "AudioLooper - File Transfer",
            subtitle: "Transfer audio files from your computer to the AudioLooper app",
            dragDropText: "📁 Drag and drop audio files here or click to select",
            selectFilesButton: "Select Files",
            supportedFormatsTitle: "📋 Supported Audio Formats",
            uploadingText: "📤 Uploading:",
            successText: "✅ Successfully uploaded:",
            failedText: "❌ Failed to upload:",
            errorText: "❌ Upload error:"
        )
    }
    
    private func createChineseSimplifiedHTML() -> String {
        return createHTMLTemplate(
            title: "AudioLooper - 文件传输",
            subtitle: "将音频文件从您的电脑传输到AudioLooper应用",
            dragDropText: "📁 拖放音频文件到这里或点击选择",
            selectFilesButton: "选择文件",
            supportedFormatsTitle: "📋 支持的音频格式",
            uploadingText: "📤 正在上传：",
            successText: "✅ 上传成功：",
            failedText: "❌ 上传失败：",
            errorText: "❌ 上传错误："
        )
    }
    
    private func createChineseTraditionalHTML() -> String {
        return createHTMLTemplate(
            title: "AudioLooper - 檔案傳輸",
            subtitle: "將音頻檔案從您的電腦傳輸到AudioLooper應用程式",
            dragDropText: "📁 拖放音頻檔案到這裡或點擊選擇",
            selectFilesButton: "選擇檔案",
            supportedFormatsTitle: "📋 支援的音頻格式",
            uploadingText: "📤 正在上傳：",
            successText: "✅ 上傳成功：",
            failedText: "❌ 上傳失敗：",
            errorText: "❌ 上傳錯誤："
        )
    }
    
    private func createHTMLTemplate(
        title: String,
        subtitle: String,
        dragDropText: String,
        selectFilesButton: String,
        supportedFormatsTitle: String,
        uploadingText: String,
        successText: String,
        failedText: String,
        errorText: String
    ) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <title>\(title)</title>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif; margin: 40px; background: #f5f5f7; }
                .container { max-width: 600px; margin: 0 auto; background: white; padding: 40px; border-radius: 12px; box-shadow: 0 4px 20px rgba(0,0,0,0.1); }
                h1 { color: #1d1d1f; text-align: center; margin-bottom: 30px; }
                .upload-area { border: 2px dashed #007AFF; border-radius: 8px; padding: 40px; text-align: center; margin: 20px 0; transition: all 0.3s; }
                .upload-area:hover { border-color: #0056b3; background: #f0f8ff; }
                .upload-area.dragover { border-color: #0056b3; background: #e6f3ff; }
                input[type="file"] { display: none; }
                .upload-btn { background: #007AFF; color: white; padding: 12px 24px; border: none; border-radius: 8px; cursor: pointer; font-size: 16px; }
                .upload-btn:hover { background: #0056b3; }
                .progress { width: 100%; height: 20px; background: #e0e0e0; border-radius: 10px; margin: 20px 0; overflow: hidden; display: none; }
                .progress-bar { height: 100%; background: #007AFF; width: 0%; transition: width 0.3s; }
                .status { margin-top: 20px; text-align: center; }
                .supported-formats { background: #f8f9fa; padding: 15px; border-radius: 8px; margin-top: 20px; }
                .supported-formats h3 { margin-top: 0; color: #666; }
                .formats { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 10px; }
                .format-tag { background: #e9ecef; padding: 4px 8px; border-radius: 4px; font-size: 12px; color: #495057; }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>🎵 \(title)</h1>
                <p style="text-align: center; color: #666; margin-bottom: 30px;">
                    \(subtitle)
                </p>
                
                <div class="upload-area" id="uploadArea">
                    <p style="margin-bottom: 20px; color: #666;">
                        \(dragDropText)
                    </p>
                    <button class="upload-btn" onclick="document.getElementById('fileInput').click()">
                        \(selectFilesButton)
                    </button>
                    <input type="file" id="fileInput" accept=".mp3,.m4a,.wav,.aac,.flac,.aiff" multiple onchange="handleFiles(this.files)">
                </div>
                
                <div class="progress" id="progress">
                    <div class="progress-bar" id="progressBar"></div>
                </div>
                
                <div class="status" id="status"></div>
                
                <div class="supported-formats">
                    <h3>\(supportedFormatsTitle)</h3>
                    <div class="formats">
                        <span class="format-tag">MP3</span>
                        <span class="format-tag">M4A</span>
                        <span class="format-tag">WAV</span>
                        <span class="format-tag">AAC</span>
                        <span class="format-tag">FLAC</span>
                        <span class="format-tag">AIFF</span>
                    </div>
                </div>
            </div>
            
            <script>
                const uploadArea = document.getElementById('uploadArea');
                const fileInput = document.getElementById('fileInput');
                const progress = document.getElementById('progress');
                const progressBar = document.getElementById('progressBar');
                const status = document.getElementById('status');
                
                const messages = {
                    uploading: '\(uploadingText)',
                    success: '\(successText)',
                    failed: '\(failedText)',
                    error: '\(errorText)'
                };
                
                // Drag and drop handlers
                uploadArea.addEventListener('dragover', (e) => {
                    e.preventDefault();
                    uploadArea.classList.add('dragover');
                });
                
                uploadArea.addEventListener('dragleave', () => {
                    uploadArea.classList.remove('dragover');
                });
                
                uploadArea.addEventListener('drop', (e) => {
                    e.preventDefault();
                    uploadArea.classList.remove('dragover');
                    handleFiles(e.dataTransfer.files);
                });
                
                function handleFiles(files) {
                    if (files.length === 0) return;
                    
                    for (let i = 0; i < files.length; i++) {
                        uploadFile(files[i]);
                    }
                }
                
                function uploadFile(file) {
                    const formData = new FormData();
                    formData.append('file', file);
                    
                    progress.style.display = 'block';
                    status.innerHTML = `${messages.uploading} ${file.name}`;
                    status.style.color = '#007AFF';
                    
                    const xhr = new XMLHttpRequest();
                    
                    xhr.upload.addEventListener('progress', (e) => {
                        if (e.lengthComputable) {
                            const percent = (e.loaded / e.total) * 100;
                            progressBar.style.width = percent + '%';
                        }
                    });
                    
                    xhr.addEventListener('load', () => {
                        if (xhr.status === 200) {
                            status.innerHTML = `${messages.success} ${file.name}`;
                            status.style.color = '#28a745';
                            progressBar.style.width = '100%';
                            setTimeout(() => {
                                progress.style.display = 'none';
                                progressBar.style.width = '0%';
                            }, 2000);
                        } else {
                            status.innerHTML = `${messages.failed} ${file.name}`;
                            status.style.color = '#dc3545';
                            progress.style.display = 'none';
                        }
                    });
                    
                    xhr.addEventListener('error', () => {
                        status.innerHTML = `${messages.error} ${file.name}`;
                        status.style.color = '#dc3545';
                        progress.style.display = 'none';
                    });
                    
                    xhr.open('POST', '/upload');
                    xhr.send(formData);
                }
            </script>
        </body>
        </html>
        """
    }
    
    private func handleFileUpload(_ request: String, connection: NWConnection) {
        DispatchQueue.main.async {
            self.isReceivingFile = true
            self.transferProgress = 0.0
        }
        
        // Parse multipart form data
        let components = request.components(separatedBy: "\r\n\r\n")
        guard components.count >= 2 else {
            send400Response(to: connection)
            return
        }
        
        // Extract boundary from Content-Type header
        let headerPart = components[0]
        guard let boundaryLine = headerPart.components(separatedBy: "\r\n").first(where: { $0.contains("boundary=") }) else {
            send400Response(to: connection)
            return
        }
        
        let boundary = String(boundaryLine.split(separator: "=").last ?? "")
        
        // Continue receiving the file data
        receiveFileData(connection: connection, boundary: boundary, existingData: request.data(using: .utf8) ?? Data())
    }
    
    private func receiveFileData(connection: NWConnection, boundary: String, existingData: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 1024) { [weak self] data, _, isComplete, error in
            var combinedData = existingData
            if let newData = data {
                combinedData.append(newData)
            }
            
            if isComplete || error != nil {
                self?.processFileData(combinedData, boundary: boundary, connection: connection)
            } else {
                self?.receiveFileData(connection: connection, boundary: boundary, existingData: combinedData)
            }
        }
    }
    
    private func processFileData(_ data: Data, boundary: String, connection: NWConnection) {
        // Parse multipart data to extract file
        guard let fileData = extractFileFromMultipart(data, boundary: boundary) else {
            send400Response(to: connection)
            return
        }
        
        // Save file to temporary location
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        do {
            try fileData.write(to: tempURL)
            
            // Validate it's an audio file
            let asset = AVURLAsset(url: tempURL)
            // Use async method for iOS 16+
            Task {
                do {
                    let tracks = try await asset.loadTracks(withMediaType: .audio)
                    if tracks.isEmpty {
                        try? FileManager.default.removeItem(at: tempURL)
                        DispatchQueue.main.async {
                            self.send400Response(to: connection, message: "Not a valid audio file")
                        }
                        return
                    }
                    
                    DispatchQueue.main.async {
                        self.receivedFileURL = tempURL
                        self.isReceivingFile = false
                        self.transferProgress = 1.0
                    }
                    
                    self.sendSuccessResponse(to: connection)
                } catch {
                    try? FileManager.default.removeItem(at: tempURL)
                    DispatchQueue.main.async {
                        self.send500Response(to: connection)
                    }
                }
            }
            
        } catch {
            print("Failed to save file: \(error)")
            send500Response(to: connection)
        }
    }
    
    private func extractFileFromMultipart(_ data: Data, boundary: String) -> Data? {
        let boundaryData = "--\(boundary)".data(using: .utf8)!
        let endBoundaryData = "--\(boundary)--".data(using: .utf8)!
        
        guard let startRange = data.range(of: boundaryData) else { return nil }
        let afterBoundary = data.subdata(in: startRange.upperBound..<data.endIndex)
        
        // Find double CRLF (end of headers)
        let doubleCRLF = "\r\n\r\n".data(using: .utf8)!
        guard let headersEnd = afterBoundary.range(of: doubleCRLF) else { return nil }
        
        let fileDataStart = headersEnd.upperBound
        
        // Find end boundary
        guard let endRange = afterBoundary.range(of: endBoundaryData) else { return nil }
        let fileDataEnd = endRange.lowerBound - 2 // Remove trailing CRLF
        
        return afterBoundary.subdata(in: fileDataStart..<fileDataEnd)
    }
    
    // MARK: - HTTP Responses
    
    private func sendSuccessResponse(to connection: NWConnection) {
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: application/json\r
        Connection: close\r
        \r
        {"status": "success", "message": "File uploaded successfully"}
        """
        
        let responseData = response.data(using: .utf8)!
        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private func send400Response(to connection: NWConnection, message: String = "Bad Request") {
        let response = """
        HTTP/1.1 400 Bad Request\r
        Content-Type: application/json\r
        Connection: close\r
        \r
        {"status": "error", "message": "\(message)"}
        """
        
        let responseData = response.data(using: .utf8)!
        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private func send404Response(to connection: NWConnection) {
        let response = """
        HTTP/1.1 404 Not Found\r
        Content-Type: text/plain\r
        Connection: close\r
        \r
        Not Found
        """
        
        let responseData = response.data(using: .utf8)!
        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private func send500Response(to connection: NWConnection) {
        let response = """
        HTTP/1.1 500 Internal Server Error\r
        Content-Type: application/json\r
        Connection: close\r
        \r
        {"status": "error", "message": "Internal server error"}
        """
        
        let responseData = response.data(using: .utf8)!
        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    // MARK: - Utility Functions
    
    private func getLocalIPAddress() {
        var address: String = ""
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                
                let interface = ptr?.pointee
                let addrFamily = interface?.ifa_addr.pointee.sa_family
                
                if addrFamily == UInt8(AF_INET) {
                    let name = String(cString: (interface!.ifa_name))
                    if name == "en0" || name == "en1" || name.hasPrefix("en") {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(interface?.ifa_addr, socklen_t((interface?.ifa_addr.pointee.sa_len)!), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                        address = String(cString: hostname)
                        break
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        
        DispatchQueue.main.async {
            self.serverIP = address
        }
    }
    
    private func showError(_ message: String) {
        DispatchQueue.main.async {
            self.errorMessage = message
            self.showError = true
        }
    }
}

// MARK: - NetService Delegate

extension NetworkTransferManager: NetServiceDelegate {
    func netServiceDidPublish(_ sender: NetService) {
        print("Bonjour service published successfully")
    }
    
    func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        print("Failed to publish Bonjour service: \(errorDict)")
    }
}
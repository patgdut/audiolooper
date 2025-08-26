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
    
    // Security improvements
    private let maxFileSize: Int64 = 100 * 1024 * 1024 // 100MB
    private let maxActiveConnections = 5
    private var activeConnections: Set<String> = []
    private let fileOperationQueue = DispatchQueue(label: "audiolooper.file.operations", qos: .utility)
    
    override init() {
        super.init()
        setupListener()
    }
    
    deinit {
        stopServer()
        cleanupTemporaryFiles()
    }
    
    private func cleanupTemporaryFiles() {
        fileOperationQueue.async {
            let tempDir = FileManager.default.temporaryDirectory
            if let enumerator = FileManager.default.enumerator(at: tempDir, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator {
                    if fileURL.lastPathComponent.contains("audiolooper") {
                        try? FileManager.default.removeItem(at: fileURL)
                    }
                }
            }
        }
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
                guard let self = self else { return }
                
                // 检查连接数限制
                guard self.activeConnections.count < self.maxActiveConnections else {
                    connection.cancel()
                    return
                }
                
                self.handleNewConnection(connection)
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
        self.isServerRunning = false
        self.connectedDevices.removeAll()
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
            guard let self = self else { return }
            
            switch state {
            case .ready:
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if let endpoint = connection.endpoint.debugDescription.components(separatedBy: ":").first {
                        if !self.connectedDevices.contains(endpoint) {
                            self.connectedDevices.append(endpoint)
                            self.activeConnections.insert(endpoint)
                        }
                    }
                }
                self.receiveHTTPRequest(connection)
            case .failed(_), .cancelled:
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if let endpoint = connection.endpoint.debugDescription.components(separatedBy: ":").first {
                        self.connectedDevices.removeAll { $0 == endpoint }
                        self.activeConnections.remove(endpoint)
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
        var receivedData = Data()
        
        func receiveMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
                guard let self = self else { return }
                
                if let data = data, !data.isEmpty {
                    receivedData.append(data)
                    
                    // 检查是否已收到完整的HTTP头部
                    if let headerEndRange = receivedData.range(of: "\r\n\r\n".data(using: .utf8)!) {
                        // 获取HTTP头部
                        let headerData = receivedData[..<headerEndRange.upperBound]
                        if let headerString = String(data: headerData, encoding: .utf8) {
                            print("HTTP Request received: \(headerString.prefix(200))...")
                            self.processHTTPRequest(receivedData, connection: connection)
                            return
                        }
                    }
                }
                
                if !isComplete && receivedData.count < 1024 * 1024 { // 1MB limit for headers
                    receiveMore()
                } else if receivedData.count >= 1024 * 1024 {
                    print("HTTP request too large")
                    self.send400Response(to: connection, message: "Request too large")
                }
            }
        }
        
        receiveMore()
    }
    
    private func processHTTPRequest(_ requestData: Data, connection: NWConnection) {
        // 提取HTTP头部进行解析
        guard let headerEndRange = requestData.range(of: "\r\n\r\n".data(using: .utf8)!) else {
            print("No HTTP header end found")
            send400Response(to: connection)
            return
        }
        
        let headerData = requestData[..<headerEndRange.lowerBound]
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            print("Cannot parse HTTP headers")
            send400Response(to: connection)
            return
        }
        
        let lines = headerString.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { 
            print("No HTTP request line found")
            send400Response(to: connection)
            return 
        }
        
        let components = firstLine.components(separatedBy: " ")
        guard components.count >= 2 else { 
            print("Invalid HTTP request line: \(firstLine)")
            send400Response(to: connection)
            return 
        }
        
        let method = components[0]
        let path = components[1]
        
        print("HTTP Request: \(method) \(path)")
        
        if method == "GET" && path == "/" {
            sendWebPage(to: connection)
        } else if method == "POST" && path == "/upload" {
            handleFileUpload(requestData, connection: connection)
        } else {
            print("Unhandled request: \(method) \(path)")
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
    
    private func handleFileUpload(_ requestData: Data, connection: NWConnection) {
        DispatchQueue.main.async {
            self.isReceivingFile = true
            self.transferProgress = 0.0
        }
        
        print("Handling file upload, data size: \(requestData.count) bytes")
        
        // 提取HTTP头部
        guard let headerEndRange = requestData.range(of: "\r\n\r\n".data(using: .utf8)!) else {
            send400Response(to: connection, message: "No HTTP header end found")
            return
        }
        
        let headerData = requestData[..<headerEndRange.lowerBound]
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            send400Response(to: connection, message: "Cannot parse HTTP headers")
            return
        }
        
        // Extract Content-Length and boundary from headers
        let lines = headerString.components(separatedBy: "\r\n")
        var contentLength: Int = 0
        var boundary: String = ""
        
        for line in lines {
            if line.lowercased().hasPrefix("content-length:") {
                if let length = Int(line.components(separatedBy: ":")[1].trimmingCharacters(in: .whitespacesAndNewlines)) {
                    contentLength = length
                }
            } else if line.lowercased().contains("content-type:") && line.contains("boundary=") {
                if let boundaryRange = line.range(of: "boundary=") {
                    boundary = String(line[boundaryRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        
        print("Content-Length: \(contentLength), Boundary: '\(boundary)'")
        
        guard !boundary.isEmpty else {
            send400Response(to: connection, message: "Missing boundary")
            return
        }
        
        guard contentLength > 0 && contentLength <= maxFileSize else {
            send400Response(to: connection, message: "Invalid content length: \(contentLength)")
            return
        }
        
        // 检查是否已经接收到完整的数据
        let bodyStartIndex = headerEndRange.upperBound
        let receivedBodySize = requestData.count - bodyStartIndex
        
        if receivedBodySize >= contentLength {
            // 已经接收到完整数据，直接处理
            print("Complete data already received")
            processMultipartData(requestData, boundary: boundary, connection: connection)
        } else {
            // 需要继续接收剩余数据
            print("Need to receive more data: \(receivedBodySize)/\(contentLength)")
            continueReceivingFileData(connection: connection, boundary: boundary, expectedLength: contentLength, existingData: requestData)
        }
    }
    
    private func continueReceivingFileData(connection: NWConnection, boundary: String, expectedLength: Int, existingData: Data) {
        var receivedData = existingData
        
        // 计算需要接收的剩余数据长度
        guard let headerEndRange = existingData.range(of: "\r\n\r\n".data(using: .utf8)!) else {
            send400Response(to: connection, message: "Invalid existing data")
            return
        }
        
        let bodyStartIndex = headerEndRange.upperBound
        let alreadyReceivedBodySize = existingData.count - bodyStartIndex
        
        func receiveChunk() {
            let totalExpectedSize = bodyStartIndex + expectedLength
            let remainingBytes = totalExpectedSize - receivedData.count
            let chunkSize = min(remainingBytes, 64 * 1024) // 64KB chunks
            
            connection.receive(minimumIncompleteLength: 1, maximumLength: chunkSize) { [weak self] data, _, isComplete, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("Error receiving data: \(error)")
                    DispatchQueue.main.async {
                        self.isReceivingFile = false
                        self.send500Response(to: connection)
                    }
                    return
                }
                
                if let data = data {
                    receivedData.append(data)
                    
                    let currentBodySize = receivedData.count - bodyStartIndex
                    DispatchQueue.main.async {
                        self.transferProgress = Double(currentBodySize) / Double(expectedLength)
                    }
                }
                
                let currentBodySize = receivedData.count - bodyStartIndex
                if currentBodySize >= expectedLength || isComplete {
                    // Finished receiving, process the data
                    print("Finished receiving data: \(currentBodySize)/\(expectedLength)")
                    self.processMultipartData(receivedData, boundary: boundary, connection: connection)
                } else {
                    // Continue receiving
                    receiveChunk()
                }
            }
        }
        
        receiveChunk()
    }
    
    private func processMultipartData(_ data: Data, boundary: String, connection: NWConnection) {
        // Parse multipart data to extract file
        guard let fileData = extractFileFromMultipart(data, boundary: boundary) else {
            DispatchQueue.main.async {
                self.isReceivingFile = false
                self.send400Response(to: connection, message: "Failed to parse multipart data")
            }
            return
        }
        
        // 验证文件大小
        guard Int64(fileData.count) <= maxFileSize else {
            DispatchQueue.main.async {
                self.isReceivingFile = false
                self.send400Response(to: connection, message: "File too large (max 100MB)")
            }
            return
        }
        
        // Save file to Documents directory with original filename
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileName = extractFileName(from: data, boundary: boundary) ?? "imported_audio_\(Date().timeIntervalSince1970).m4a"
        let permanentURL = documentsURL.appendingPathComponent(fileName)
        
        // 使用异步队列进行文件操作
        fileOperationQueue.async {
            do {
                try fileData.write(to: permanentURL)
            
                // Validate it's an audio file
                let asset = AVURLAsset(url: permanentURL)
                // Use async method for iOS 16+
                Task {
                    do {
                        let tracks = try await asset.loadTracks(withMediaType: .audio)
                        if tracks.isEmpty {
                            try? FileManager.default.removeItem(at: permanentURL)
                            DispatchQueue.main.async {
                                self.isReceivingFile = false
                                self.send400Response(to: connection, message: "Not a valid audio file")
                            }
                            return
                        }
                        
                        DispatchQueue.main.async {
                            self.receivedFileURL = permanentURL
                            self.isReceivingFile = false
                            self.transferProgress = 1.0
                        }
                        
                        self.sendSuccessResponse(to: connection)
                    } catch {
                        try? FileManager.default.removeItem(at: permanentURL)
                        DispatchQueue.main.async {
                            self.isReceivingFile = false
                            self.send500Response(to: connection)
                        }
                    }
                }
                
            } catch {
                print("Failed to save file: \(error)")
                DispatchQueue.main.async {
                    self.isReceivingFile = false
                    self.send500Response(to: connection)
                }
            }
        }
    }
    
    private func extractFileFromMultipart(_ data: Data, boundary: String) -> Data? {
        print("Parsing multipart data, size: \(data.count) bytes")
        
        // 查找HTTP头部结束位置（双换行符）
        let headerEndMarker = "\r\n\r\n".data(using: .utf8)!
        guard let headerEndRange = data.range(of: headerEndMarker) else {
            print("Could not find HTTP headers end")
            return nil
        }
        
        // 只对HTTP头部进行字符串解析
        let headerData = data[..<headerEndRange.lowerBound]
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            print("Could not parse HTTP headers")
            return nil
        }
        
        print("HTTP Headers parsed successfully")
        
        // 在HTTP头部查找boundary
        var parsedBoundary: String?
        let lines = headerString.components(separatedBy: .newlines)
        
        for line in lines {
            if line.contains("boundary=") {
                let parts = line.components(separatedBy: "boundary=")
                if parts.count >= 2 {
                    parsedBoundary = parts[1].components(separatedBy: .whitespacesAndNewlines)[0].trimmingCharacters(in: CharacterSet(charactersIn: "\"';"))
                    break
                }
            }
        }
        
        // 使用传入的boundary或解析出的boundary
        let useBoundary = parsedBoundary ?? boundary
        guard !useBoundary.isEmpty else {
            print("No boundary found in headers")
            return nil
        }
        
        print("Found boundary: '\(useBoundary)'")
        
        // 从HTTP body开始查找multipart数据
        let bodyStart = headerEndRange.upperBound
        let bodyData = data[bodyStart...]
        
        // 查找第一个boundary
        let boundaryMarker = "--\(useBoundary)".data(using: .utf8)!
        guard let firstBoundaryRange = bodyData.range(of: boundaryMarker) else {
            print("First boundary not found in body")
            return nil
        }
        
        let afterBoundary = bodyData[firstBoundaryRange.upperBound...]
        
        // 查找multipart header结束位置
        let multipartHeaderEnd = "\r\n\r\n".data(using: .utf8)!
        guard let multipartHeaderEndRange = afterBoundary.range(of: multipartHeaderEnd) else {
            print("Multipart header end not found")
            return nil
        }
        
        let fileStart = multipartHeaderEndRange.upperBound
        
        // 查找结束boundary
        let endBoundary = "\r\n--\(useBoundary)--".data(using: .utf8)!
        if let endRange = bodyData.range(of: endBoundary, in: fileStart..<bodyData.endIndex) {
            let fileData = bodyData[fileStart..<endRange.lowerBound]
            print("Successfully extracted file data: \(fileData.count) bytes")
            return Data(fileData)
        } else {
            // 如果找不到结束boundary，可能是简单的结束标记
            let simpleBoundary = "\r\n--\(useBoundary)".data(using: .utf8)!
            if let endRange = bodyData.range(of: simpleBoundary, in: fileStart..<bodyData.endIndex) {
                let fileData = bodyData[fileStart..<endRange.lowerBound]
                print("Successfully extracted file data (simple boundary): \(fileData.count) bytes")
                return Data(fileData)
            } else {
                print("Could not find end boundary, using remaining data")
                let fileData = bodyData[fileStart...]
                return Data(fileData)
            }
        }
    }
    
    private func extractFileName(from data: Data, boundary: String) -> String? {
        // 查找HTTP头部结束位置（双换行符）
        let headerEndMarker = "\r\n\r\n".data(using: .utf8)!
        guard let headerEndRange = data.range(of: headerEndMarker) else { return nil }
        
        // 从HTTP body开始查找multipart数据
        let bodyStart = headerEndRange.upperBound
        let bodyData = data[bodyStart...]
        
        // 在HTTP头部查找boundary（如果需要）
        let headerData = data[..<headerEndRange.lowerBound]
        var useBoundary = boundary
        
        if let headerString = String(data: headerData, encoding: .utf8) {
            let lines = headerString.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("boundary=") {
                    let parts = line.components(separatedBy: "boundary=")
                    if parts.count >= 2 {
                        useBoundary = parts[1].components(separatedBy: .whitespacesAndNewlines)[0].trimmingCharacters(in: CharacterSet(charactersIn: "\"';"))
                        break
                    }
                }
            }
        }
        
        // 查找第一个boundary
        let boundaryMarker = "--\(useBoundary)".data(using: .utf8)!
        guard let firstBoundaryRange = bodyData.range(of: boundaryMarker) else { return nil }
        
        let afterBoundary = bodyData[firstBoundaryRange.upperBound...]
        
        // 查找multipart header结束位置
        let multipartHeaderEnd = "\r\n\r\n".data(using: .utf8)!
        guard let multipartHeaderEndRange = afterBoundary.range(of: multipartHeaderEnd) else { return nil }
        
        // 获取multipart headers
        let multipartHeadersData = afterBoundary[..<multipartHeaderEndRange.lowerBound]
        guard let multipartHeaders = String(data: multipartHeadersData, encoding: .utf8) else { return nil }
        
        // Find filename in Content-Disposition header
        let lines = multipartHeaders.components(separatedBy: .newlines)
        for line in lines {
            if line.lowercased().contains("content-disposition") && line.contains("filename=") {
                // Extract filename from: filename="example.mp3"
                if let range = line.range(of: "filename=\"") {
                    let afterFilename = String(line[range.upperBound...])
                    if let endQuote = afterFilename.firstIndex(of: "\"") {
                        let fileName = String(afterFilename[..<endQuote])
                        return fileName.isEmpty ? nil : fileName
                    }
                }
            }
        }
        
        return nil
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
        
        DispatchQueue.main.async { [weak self] in
            self?.serverIP = address
        }
    }
    
    private func showError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.errorMessage = message
            self?.showError = true
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

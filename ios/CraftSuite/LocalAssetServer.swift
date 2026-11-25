import Foundation
import Network

final class LocalAssetServer: ObservableObject {
    @Published private(set) var port: UInt16?
    @Published private(set) var errorMessage: String?

    private let queue = DispatchQueue(label: "io.github.craftsuite.localserver", qos: .userInitiated)
    private var listener: NWListener?
    private var openedFiles: [String: URL] = [:]
    private let lock = NSLock()

    private let preferredPort: UInt16 = 48771

    private var webBundleRoot: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("WebBundle", isDirectory: true)
    }

    func start() {
        guard listener == nil else { return }
        startListener(on: NWEndpoint.Port(rawValue: preferredPort), allowFallback: true)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async {
            self.port = nil
        }
    }

    func registerOpenedFile(from externalURL: URL) -> (app: CraftAppKind, queryPath: String)? {
        let ext = externalURL.pathExtension
        guard let targetApp = CraftAppKind.from(fileExtension: ext) else {
            return nil
        }

        let needsSecurityScope = externalURL.startAccessingSecurityScopedResource()
        defer {
            if needsSecurityScope {
                externalURL.stopAccessingSecurityScopedResource()
            }
        }

        let token = UUID().uuidString.lowercased()
        let filename = externalURL.lastPathComponent.isEmpty ? "document.\(ext)" : externalURL.lastPathComponent
        let destDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CraftSuiteOpened", isDirectory: true)
            .appendingPathComponent(token, isDirectory: true)
        let destURL = destDir.appendingPathComponent(filename)

        do {
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: externalURL, to: destURL)
        } catch {
            return nil
        }

        lock.lock()
        openedFiles[token] = destURL
        lock.unlock()

        let encodedName = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename
        return (targetApp, "/opened/\(token)/\(encodedName)")
    }

    private func startListener(on requestedPort: NWEndpoint.Port?, allowFallback: Bool) {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        if let requestedPort = requestedPort {
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: requestedPort)
        } else {
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        }

        do {
            let newListener = try NWListener(using: parameters)
            self.listener = newListener

            newListener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    if let assignedPort = newListener.port?.rawValue {
                        DispatchQueue.main.async {
                            self.port = assignedPort
                            self.errorMessage = nil
                        }
                    }
                case .failed(let error):
                    newListener.cancel()
                    if allowFallback {
                        self.listener = nil
                        self.startListener(on: nil, allowFallback: false)
                    } else {
                        DispatchQueue.main.async {
                            self.errorMessage = "Local server failed: \(error.localizedDescription)"
                        }
                    }
                default:
                    break
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection: connection)
            }

            newListener.start(queue: queue)
        } catch {
            if allowFallback {
                startListener(on: nil, allowFallback: false)
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "Cannot bind local server: \(error.localizedDescription)"
                }
            }
        }
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else {
                connection.cancel()
                return
            }

            if error != nil {
                connection.cancel()
                return
            }

            var accumulated = buffer
            if let data = data {
                accumulated.append(data)
            }

            if let headerEnd = accumulated.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = accumulated[..<headerEnd.lowerBound]
                let response = self.buildResponse(for: headerData)
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }

            if accumulated.count > 65536 || isComplete {
                let response = self.simpleResponse(status: "400 Bad Request", body: Data("Bad Request".utf8), mimeType: "text/plain; charset=utf-8")
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }

            self.receiveRequest(on: connection, buffer: accumulated)
        }
    }

    private func buildResponse(for headerData: Data) -> Data {
        guard let headerString = String(data: headerData, encoding: .utf8),
              let requestLine = headerString.components(separatedBy: "\r\n").first else {
            return simpleResponse(status: "400 Bad Request", body: Data("Bad Request".utf8), mimeType: "text/plain; charset=utf-8")
        }

        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2 else {
            return simpleResponse(status: "400 Bad Request", body: Data("Bad Request".utf8), mimeType: "text/plain; charset=utf-8")
        }

        let method = String(parts[0]).uppercased()
        guard method == "GET" || method == "HEAD" else {
            return simpleResponse(status: "405 Method Not Allowed", body: Data("Method Not Allowed".utf8), mimeType: "text/plain; charset=utf-8")
        }

        let rawTarget = String(parts[1])
        let pathOnly = rawTarget.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? "/"

        // Redirect /gridcraft -> /gridcraft/ so relative Trunk URLs resolve properly.
        for app in CraftAppKind.allCases where pathOnly == "/\(app.folderName)" {
            return redirectResponse(location: "/\(app.folderName)/")
        }

        // Serve temporary opened files at /opened/<token>/<filename>
        if pathOnly.hasPrefix("/opened/") {
            let trimmed = String(pathOnly.dropFirst("/opened/".count))
            let segments = trimmed.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            if let token = segments.first.map(String.init) {
                lock.lock()
                let fileURL = openedFiles[token]
                lock.unlock()

                if let fileURL = fileURL, let fileData = try? Data(contentsOf: fileURL) {
                    let mime = mimeType(forExtension: fileURL.pathExtension)
                    return okResponse(body: method == "HEAD" ? Data() : fileData, contentLength: fileData.count, mimeType: mime)
                }
            }
            return simpleResponse(status: "404 Not Found", body: Data("File not found".utf8), mimeType: "text/plain; charset=utf-8")
        }

        guard let bundleRoot = webBundleRoot else {
            return simpleResponse(status: "500 Internal Server Error", body: Data("WebBundle missing".utf8), mimeType: "text/plain; charset=utf-8")
        }

        let decodedPath = pathOnly.removingPercentEncoding ?? pathOnly
        var relative = decodedPath.hasPrefix("/") ? String(decodedPath.dropFirst()) : decodedPath
        if relative.isEmpty || relative.hasSuffix("/") {
            relative += "index.html"
        }

        let components = relative.split(separator: "/").map(String.init)
        if components.contains("..") || components.contains(".") || components.isEmpty {
            return simpleResponse(status: "403 Forbidden", body: Data("Forbidden".utf8), mimeType: "text/plain; charset=utf-8")
        }

        var targetURL = bundleRoot
        for component in components {
            targetURL.appendPathComponent(component, isDirectory: false)
        }

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDir) && isDir.boolValue {
            targetURL.appendPathComponent("index.html", isDirectory: false)
        }

        let resolvedTarget = targetURL.standardizedFileURL.path
        let resolvedRoot = bundleRoot.standardizedFileURL.path
        guard resolvedTarget.hasPrefix(resolvedRoot),
              let data = try? Data(contentsOf: targetURL) else {
            return simpleResponse(status: "404 Not Found", body: Data("Not Found".utf8), mimeType: "text/plain; charset=utf-8")
        }

        let mime = mimeType(forExtension: targetURL.pathExtension)
        return okResponse(body: method == "HEAD" ? Data() : data, contentLength: data.count, mimeType: mime)
    }

    private func okResponse(body: Data, contentLength: Int, mimeType: String) -> Data {
        var header = "HTTP/1.1 200 OK\r\n"
        header += "Content-Type: \(mimeType)\r\n"
        header += "Content-Length: \(contentLength)\r\n"
        header += "X-Content-Type-Options: nosniff\r\n"
        header += "Cross-Origin-Opener-Policy: same-origin\r\n"
        header += "Cache-Control: no-cache\r\n"
        header += "Connection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        return response
    }

    private func redirectResponse(location: String) -> Data {
        var header = "HTTP/1.1 301 Moved Permanently\r\n"
        header += "Location: \(location)\r\n"
        header += "Content-Length: 0\r\n"
        header += "Connection: close\r\n\r\n"
        return Data(header.utf8)
    }

    private func simpleResponse(status: String, body: Data, mimeType: String) -> Data {
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(mimeType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        return response
    }

    private func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm":
            return "text/html; charset=utf-8"
        case "js", "mjs":
            return "text/javascript; charset=utf-8"
        case "wasm":
            return "application/wasm"
        case "css":
            return "text/css; charset=utf-8"
        case "json":
            return "application/json; charset=utf-8"
        case "svg":
            return "image/svg+xml"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "ico":
            return "image/x-icon"
        case "woff2":
            return "font/woff2"
        case "woff":
            return "font/woff"
        case "ttf":
            return "font/ttf"
        case "onnx", "bin":
            return "application/octet-stream"
        case "pdf":
            return "application/pdf"
        case "xlsx":
            return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "docx":
            return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "csv":
            return "text/csv; charset=utf-8"
        case "txt", "md":
            return "text/plain; charset=utf-8"
        default:
            return "application/octet-stream"
        }
    }
}

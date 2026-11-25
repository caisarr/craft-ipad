import SwiftUI

struct ContentView: View {
    @ObservedObject var server: LocalAssetServer
    @Binding var selectedApp: CraftAppKind
    @Binding var openedFileQuery: String?

    @State private var useWebGL: Bool = false
    @State private var hideToolbar: Bool = false
    @State private var isLoading: Bool = true
    @State private var statusError: String?
    @State private var reloadToken: Int = 0

    private var hasWebBundle: Bool {
        Bundle.main.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "WebBundle/\(selectedApp.folderName)"
        ) != nil
    }

    private func targetURL(port: UInt16) -> URL? {
        var urlString = "http://127.0.0.1:\(port)/\(selectedApp.folderName)/"
        var queryItems: [String] = []
        if useWebGL {
            queryItems.append("webgl")
        }
        if let opened = openedFileQuery, !opened.isEmpty {
            let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+"))
            let encoded = opened.addingPercentEncoding(withAllowedCharacters: allowed) ?? opened
            queryItems.append("file=\(encoded)")
        }
        if !queryItems.isEmpty {
            urlString += "?" + queryItems.joined(separator: "&")
        }
        return URL(string: urlString)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                if !hideToolbar {
                    toolbar
                }

                contentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(uiColor: .systemBackground))

            if hideToolbar {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        hideToolbar = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: selectedApp.sfSymbol)
                        Text("Toolbar")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .shadow(radius: 4)
                }
                .padding(.top, 10)
                .padding(.trailing, 14)
            }
        }
        .onChange(of: selectedApp) { _, _ in
            statusError = nil
            isLoading = true
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("Application", selection: Binding(
                get: { selectedApp },
                set: { nextApp in
                    openedFileQuery = nil
                    selectedApp = nextApp
                }
            )) {
                ForEach(CraftAppKind.allCases) { app in
                    Label(app.displayName, systemImage: app.sfSymbol)
                        .tag(app)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)

            Spacer(minLength: 8)

            Button {
                useWebGL.toggle()
                reloadToken += 1
            } label: {
                Label(useWebGL ? "WebGL2" : "Auto GPU", systemImage: "cpu")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(useWebGL ? selectedApp.accentColor.opacity(0.18) : Color.secondary.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Toggle WebGL2 fallback if WebGPU has rendering issues")

            Button {
                statusError = nil
                reloadToken += 1
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.body.weight(.medium))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .help("Reload current app")

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    hideToolbar = true
                }
            } label: {
                Image(systemName: "eye.slash")
                    .font(.body.weight(.medium))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .help("Hide toolbar for fullscreen canvas")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(Divider(), alignment: .bottom)
    }

    @ViewBuilder
    private var contentArea: some View {
        if let serverError = server.errorMessage {
            placeholderView(
                symbol: "exclamationmark.triangle.fill",
                title: "Local Server Error",
                detail: serverError
            )
        } else if !hasWebBundle {
            placeholderView(
                symbol: "shippingbox",
                title: "\(selectedApp.displayName) Bundle Missing",
                detail: "WebBundle/\(selectedApp.folderName)/index.html was not bundled in this build. Run scripts/fetch-web-bundles.sh before archiving."
            )
        } else if let port = server.port, let url = targetURL(port: port) {
            ZStack {
                CraftWebView(url: url, isLoading: $isLoading, statusError: $statusError)
                    .id("\(selectedApp.rawValue)-\(useWebGL ? "webgl" : "auto")-\(reloadToken)-\(openedFileQuery ?? "")")

                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Loading \(selectedApp.displayName)…")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }

                if let err = statusError {
                    placeholderView(
                        symbol: "wifi.exclamationmark",
                        title: "Failed to Load \(selectedApp.displayName)",
                        detail: err
                    )
                }
            }
        } else {
            VStack(spacing: 12) {
                ProgressView()
                Text("Starting local runtime…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func placeholderView(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 40))
                .foregroundStyle(selectedApp.accentColor)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Retry") {
                statusError = nil
                reloadToken += 1
            }
            .buttonStyle(.borderedProminent)
            .tint(selectedApp.accentColor)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }
}

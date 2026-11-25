import SwiftUI

@main
struct CraftSuiteApp: App {
    @StateObject private var server = LocalAssetServer()
    @State private var selectedApp: CraftAppKind = .gridcraft
    @State private var openedFileQuery: String?

    var body: some Scene {
        WindowGroup {
            ContentView(
                server: server,
                selectedApp: $selectedApp,
                openedFileQuery: $openedFileQuery
            )
            .onAppear {
                server.start()
            }
            .onOpenURL { url in
                if let result = server.registerOpenedFile(from: url) {
                    selectedApp = result.app
                    openedFileQuery = result.queryPath
                }
            }
        }
    }
}

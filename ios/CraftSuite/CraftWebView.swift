import SwiftUI
import UIKit
import WebKit

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(_ delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

struct CraftWebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var statusError: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        WebViewKeyboardSupport.install()

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let userContentController = WKUserContentController()
        let downloadBridgeScript = WKUserScript(
            source: Self.blobDownloadBridgeJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(downloadBridgeScript)
        userContentController.addUserScript(WKUserScript(
            source: WebViewKeyboardSupport.canvasFocusBridgeJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        userContentController.add(WeakScriptMessageHandler(context.coordinator), name: "craftDownload")
        config.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = UIColor.systemBackground
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        // Hardware keyboard events only reach the page while the web view is first responder.
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.claimKeyboardFocus))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        tap.delegate = context.coordinator
        webView.addGestureRecognizer(tap)
        context.coordinator.webView = webView

        context.coordinator.currentURL = url
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.currentURL != url {
            context.coordinator.currentURL = url
            webView.load(URLRequest(url: url))
        }
    }

    // Intercept <a download href="blob:...|data:..."> clicks and forward bytes safely via FileReader.
    private static let blobDownloadBridgeJS = """
    (function() {
      if (window.__craftDownloadHooked) return;
      window.__craftDownloadHooked = true;

      function sendBlobToNative(blob, filename) {
        try {
          var reader = new FileReader();
          reader.onloadend = function() {
            if (typeof reader.result === 'string' &&
                window.webkit &&
                window.webkit.messageHandlers &&
                window.webkit.messageHandlers.craftDownload) {
              window.webkit.messageHandlers.craftDownload.postMessage({
                filename: filename || 'export.bin',
                dataUrl: reader.result
              });
            }
          };
          reader.readAsDataURL(blob);
        } catch (err) {
          console.error('Craft download bridge error:', err);
        }
      }

      var origClick = HTMLAnchorElement.prototype.click;
      HTMLAnchorElement.prototype.click = function() {
        var href = this.getAttribute('href') || this.href || '';
        var hasDownload = this.hasAttribute('download');
        if (hasDownload && (href.indexOf('blob:') === 0 || href.indexOf('data:') === 0)) {
          var name = this.getAttribute('download') || 'export.bin';
          if (href.indexOf('data:') === 0 && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.craftDownload) {
            window.webkit.messageHandlers.craftDownload.postMessage({
              filename: name,
              dataUrl: href
            });
            return;
          }
          fetch(href)
            .then(function(res) { return res.blob(); })
            .then(function(blob) { sendBlobToNative(blob, name); })
            .catch(function() {});
          return;
        }
        return origClick.apply(this, arguments);
      };
    })();
    """

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate, UIDocumentPickerDelegate, UIGestureRecognizerDelegate {
        var parent: CraftWebView
        var currentURL: URL?
        weak var webView: WKWebView?
        private var pendingDownloadURL: URL?

        init(parent: CraftWebView) {
            self.parent = parent
        }

        @objc func claimKeyboardFocus() {
            guard let webView = webView, !webView.isFirstResponder else { return }
            webView.becomeFirstResponder()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        // WebKit private UI delegate hook (iOS 13+): allow focus from page script to open the keyboard.
        @objc(_webView:focusShouldStartInputSession:)
        func webView(_ webView: WKWebView, focusShouldStartInputSession focusedElementInfo: AnyObject) -> Bool {
            true
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = true
                self.parent.statusError = nil
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                webView.becomeFirstResponder()
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.statusError = error.localizedDescription
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.statusError = error.localizedDescription
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.shouldPerformDownload {
                decisionHandler(.download)
                return
            }

            if let targetURL = navigationAction.request.url {
                let host = targetURL.host ?? ""
                let scheme = targetURL.scheme?.lowercased() ?? ""
                if (scheme == "http" || scheme == "https") && host != "127.0.0.1" && host != "localhost" {
                    UIApplication.shared.open(targetURL)
                    decisionHandler(.cancel)
                    return
                }
            }

            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            if navigationResponse.canShowMIMEType {
                decisionHandler(.allow)
            } else {
                decisionHandler(.download)
            }
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = self
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                let host = url.host ?? ""
                if host == "127.0.0.1" || host == "localhost" {
                    webView.load(navigationAction.request)
                } else {
                    UIApplication.shared.open(url)
                }
            }
            return nil
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping () -> Void
        ) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            if presentAlert(alert) == nil { completionHandler() }
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (Bool) -> Void
        ) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
            if presentAlert(alert) == nil { completionHandler(false) }
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptTextInputPanelWithPrompt prompt: String,
            defaultText: String?,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (String?) -> Void
        ) {
            let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                completionHandler(alert.textFields?.first?.text)
            })
            if presentAlert(alert) == nil { completionHandler(nil) }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "craftDownload",
                  let payload = message.body as? [String: Any],
                  let dataUrl = payload["dataUrl"] as? String else {
                return
            }

            let rawFilename = (payload["filename"] as? String) ?? "export.bin"
            let safeName = sanitizeFilename(rawFilename)

            guard let commaIndex = dataUrl.firstIndex(of: ",") else { return }
            let base64Part = String(dataUrl[dataUrl.index(after: commaIndex)...])
            guard let fileData = Data(base64Encoded: base64Part, options: .ignoreUnknownCharacters) else { return }

            let exportURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent(safeName)

            do {
                try FileManager.default.createDirectory(at: exportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileData.write(to: exportURL, options: .atomic)
                DispatchQueue.main.async {
                    self.presentExportPicker(for: exportURL)
                }
            } catch {
                DispatchQueue.main.async {
                    self.parent.statusError = "Failed to export \(safeName): \(error.localizedDescription)"
                }
            }
        }

        func download(
            _ download: WKDownload,
            decideDestinationUsing response: URLResponse,
            suggestedFilename: String,
            completionHandler: @escaping (URL?) -> Void
        ) {
            let safeName = sanitizeFilename(suggestedFilename)
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent(safeName)
            try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            pendingDownloadURL = dest
            completionHandler(dest)
        }

        func downloadDidFinish(_ download: WKDownload) {
            guard let url = pendingDownloadURL else { return }
            pendingDownloadURL = nil
            DispatchQueue.main.async {
                self.presentExportPicker(for: url)
            }
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            pendingDownloadURL = nil
            DispatchQueue.main.async {
                self.parent.statusError = "Download failed: \(error.localizedDescription)"
            }
        }

        private func presentExportPicker(for fileURL: URL) {
            guard let presenter = topViewController() else { return }
            let picker = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
            picker.delegate = self
            presenter.present(picker, animated: true)
        }

        @discardableResult
        private func presentAlert(_ alert: UIAlertController) -> Void? {
            guard let presenter = topViewController() else { return nil }
            presenter.present(alert, animated: true)
            return ()
        }

        private func topViewController() -> UIViewController? {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let root = scenes.flatMap { $0.windows }.first(where: { $0.isKeyWindow })?.rootViewController
            var current = root
            while let presented = current?.presentedViewController {
                current = presented
            }
            return current
        }

        private func sanitizeFilename(_ name: String) -> String {
            let base = (name as NSString).lastPathComponent
            let cleaned = base.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? "export.bin" : cleaned
        }
    }
}

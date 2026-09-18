import Combine
import SwiftUI
import WebKit

/// A private in-app browser for links tapped in a conversation. Backed by
/// a `WKWebView` configured with a *non-persistent* data store: cookies,
/// cache, and browsing state live only in memory for the life of this
/// view and are discarded the moment it's dismissed — nothing is written
/// to disk, and none of it is shared with the system's own Safari
/// history/cookies/autofill. There's deliberately no "Open in Safari"
/// escape hatch here — that would hand the URL to a browser that *does*
/// keep history, defeating the point.
struct InAppBrowserView: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = WebViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                WebView(url: url, model: model)
                if model.isLoading {
                    ProgressView()
                }
            }
            .navigationTitle(model.pageTitle ?? url.host ?? "Browser")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { model.goBack() } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!model.canGoBack)

                    Button { model.goForward() } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!model.canGoForward)

                    Spacer()

                    Button { model.reload() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }
}

@MainActor
final class WebViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var pageTitle: String?

    fileprivate weak var webView: WKWebView?

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }
}

private struct WebView: UIViewRepresentable {
    let url: URL
    let model: WebViewModel

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // The whole point: an ephemeral store means no history, cookies,
        // or cache ever touch disk or the system's shared Safari data.
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        model.webView = webView
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let model: WebViewModel

        init(model: WebViewModel) {
            self.model = model
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            model.isLoading = true
            refresh(webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            refresh(webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model.isLoading = false
            refresh(webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            model.isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            model.isLoading = false
        }

        private func refresh(_ webView: WKWebView) {
            model.canGoBack = webView.canGoBack
            model.canGoForward = webView.canGoForward
            model.pageTitle = webView.title?.isEmpty == false ? webView.title : nil
        }
    }
}

import SwiftUI
import WebKit
import UIKit

/// Native VR-OS app entries. Websites remain subject to their providers'
/// login, DRM and embedded-browser restrictions.
enum VRWebApp: String, CaseIterable, Identifiable {
    case youtube
    case netflix
    case browser

    var id: String { rawValue }
    var title: String {
        switch self {
        case .youtube: return "YouTube"
        case .netflix: return "Netflix"
        case .browser: return "Navegador"
        }
    }
    var symbol: String {
        switch self {
        case .youtube: return "play.rectangle.fill"
        case .netflix: return "film.stack.fill"
        case .browser: return "globe"
        }
    }
    var startURL: URL {
        switch self {
        case .youtube: return URL(string: "https://m.youtube.com")!
        case .netflix: return URL(string: "https://www.netflix.com/br/")!
        case .browser: return URL(string: "https://www.google.com")!
        }
    }
    var description: String {
        switch self {
        case .youtube: return "Vídeos e pesquisas"
        case .netflix: return "Site da plataforma · DRM pode limitar reprodução"
        case .browser: return "Explore qualquer site HTTPS"
        }
    }
    var accent: Color {
        switch self {
        case .youtube: return Color(red: 0.97, green: 0.22, blue: 0.24)
        case .netflix: return Color(red: 0.84, green: 0.12, blue: 0.18)
        case .browser: return Color(red: 0.25, green: 0.67, blue: 1)
        }
    }
}

/// A single navigation session backs the two stereo web surfaces. WebKit
/// requires a UIView in each eye; only the left viewport drives navigation
/// and audio. The right is a muted, noninteractive visual companion.
@MainActor
final class VRWebSession: ObservableObject {
    let app: VRWebApp
    @Published var address: String
    @Published private(set) var requestedURL: URL
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published var loading = false
    @Published var message: String?

    weak var primary: WKWebView?
    weak var secondary: WKWebView?

    init(app: VRWebApp) {
        self.app = app
        requestedURL = app.startURL
        address = app.startURL.absoluteString
        message = app == .netflix
            ? "Filmes protegidos podem não tocar aqui. Use Safari se necessário."
            : nil
    }

    func navigate() {
        let input = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        var target: URL?
        if input.contains(" ") || (!input.contains(".") && !input.contains("://")) {
            var components = URLComponents(string: "https://www.google.com/search")
            components?.queryItems = [URLQueryItem(name: "q", value: input)]
            target = components?.url
        } else {
            target = URL(string: input.contains("://") ? input : "https://" + input)
        }
        guard let url = target, url.scheme?.lowercased() == "https",
              url.host != nil else {
            message = "Digite um endereço HTTPS válido ou um termo de pesquisa."
            return
        }
        message = nil
        requestedURL = url
    }

    func goHome() {
        requestedURL = app.startURL
        address = requestedURL.absoluteString
        message = nil
    }

    func back() {
        if primary?.canGoBack == true {
            primary?.goBack()
            if secondary?.canGoBack == true { secondary?.goBack() }
        }
    }

    func forward() {
        if primary?.canGoForward == true {
            primary?.goForward()
            if secondary?.canGoForward == true { secondary?.goForward() }
        }
    }

    func reload() {
        primary?.reload()
        secondary?.reload()
    }

    func didLoad(_ webView: WKWebView) {
        // Only the primary updates shared location; prevents a feedback loop.
        guard webView === primary else { return }
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        loading = webView.isLoading
        if let url = webView.url, url.scheme == "https" {
            address = url.absoluteString
            if requestedURL != url { requestedURL = url }
        }
    }

    func mirrorScroll(from offset: CGPoint) {
        guard let secondary = secondary else { return }
        secondary.scrollView.setContentOffset(offset, animated: false)
    }

    func openInSafari() {
        guard let url = URL(string: address), url.scheme == "https" else {
            UIApplication.shared.open(requestedURL)
            return
        }
        UIApplication.shared.open(url)
    }
}

private struct VRWebSurface: UIViewRepresentable {
    @ObservedObject var session: VRWebSession
    let rightEye: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, rightEye: rightEye)
    }

    func makeUIView(context: Context) -> WKWebView {
        let settings = WKWebViewConfiguration()
        settings.websiteDataStore = .default()
        settings.allowsInlineMediaPlayback = true
        settings.mediaTypesRequiringUserActionForPlayback = [.audio, .video]

        // The right eye must never play audible media in parallel. Mute
        // media elements at document start and follow DOM insertions.
        if rightEye {
            let script = """
            (() => {
              const mute = () => document.querySelectorAll('video,audio')
                .forEach(el => { el.muted = true; el.volume = 0; });
              document.addEventListener('DOMContentLoaded', () => {
                mute();
                new MutationObserver(mute).observe(document.documentElement,
                  {subtree:true,childList:true});
              });
            })();
            """
            settings.userContentController.addUserScript(WKUserScript(
                source: script, injectionTime: .atDocumentStart,
                forMainFrameOnly: false))
        }

        let view = WKWebView(frame: .zero, configuration: settings)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.scrollView.bounces = false
        view.isOpaque = false
        view.backgroundColor = UIColor.black
        view.scrollView.backgroundColor = UIColor.black
        view.isUserInteractionEnabled = !rightEye
        if rightEye {
            session.secondary = view
        } else {
            session.primary = view
            context.coordinator.scrollObservation =
                view.scrollView.observe(\.contentOffset, options: [.new]) {
                    [weak session] scroll, _ in
                    DispatchQueue.main.async {
                        session?.mirrorScroll(from: scroll.contentOffset)
                    }
                }
        }
        context.coordinator.loadedURL = session.requestedURL
        view.load(URLRequest(url: session.requestedURL))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != session.requestedURL else { return }
        context.coordinator.loadedURL = session.requestedURL
        if view.url != session.requestedURL {
            view.load(URLRequest(url: session.requestedURL))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let session: VRWebSession
        let rightEye: Bool
        var loadedURL: URL?
        var scrollObservation: NSKeyValueObservation?

        init(session: VRWebSession, rightEye: Bool) {
            self.session = session
            self.rightEye = rightEye
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            if !rightEye { session.loading = true }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            session.didLoad(webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            guard !rightEye else { return }
            session.loading = false
            session.message = "Site indisponível: " + error.localizedDescription
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!,
                     withError error: Error) {
            guard !rightEye else { return }
            session.loading = false
            session.message = error.localizedDescription
        }

        // Sites often open login/search pages in a new tab. Reuse the same
        // window instead of presenting an invisible pop-up inside the VR box.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil,
               let url = navigationAction.request.url, url.scheme == "https" {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}

struct VRWebWindow: View {
    @ObservedObject var session: VRWebSession
    let rightEye: Bool

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                TextField("Endereço ou pesquisa", text: $session.address)
                    .font(.system(size: 11))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .onSubmit { session.navigate() }
                    .disabled(rightEye)
                    .padding(.horizontal, 7)
                    .frame(height: 30)
                    .background(Color.white.opacity(0.11),
                                in: RoundedRectangle(cornerRadius: 7))
                navButton("arrow.right", disabled: false) { session.navigate() }
            }
            HStack(spacing: 4) {
                navButton("chevron.left", disabled: !session.canGoBack) {
                    session.back()
                }
                navButton("chevron.right", disabled: !session.canGoForward) {
                    session.forward()
                }
                navButton("arrow.clockwise", disabled: false) { session.reload() }
                navButton("house.fill", disabled: false) { session.goHome() }
                navButton("safari", disabled: false) { session.openInSafari() }
                if session.loading { ProgressView().scaleEffect(0.65) }
            }
            .frame(height: 27)

            VRWebSurface(session: session, rightEye: rightEye)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 7))

            if let message = session.message {
                Text(message)
                    .font(.system(size: 9))
                    .lineLimit(2)
                    .foregroundStyle(.yellow.opacity(0.95))
            } else {
                Text(session.app == .netflix
                     ? "Reprodução protegida pode exigir Safari"
                     : "Toque para navegar · alça branca para mover")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.67))
                    .lineLimit(1)
            }
        }
    }

    private func navButton(_ icon: String, disabled: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 27)
                .background(.white.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
}

import SwiftUI
import WebKit
import UIKit

/// Native VR-OS app entries. Websites remain subject to their providers'
/// login, DRM and embedded-browser restrictions.
enum VRWebApp: String, CaseIterable, Identifiable {
    case youtube
    case netflix
    case browser
    case wikipedia
    case twitch

    var id: String { rawValue }
    var title: String {
        switch self {
        case .youtube: return "YouTube"
        case .netflix: return "Netflix"
        case .browser: return "Navegador"
        case .wikipedia: return "Wikipedia"
        case .twitch: return "Twitch"
        }
    }
    var symbol: String {
        switch self {
        case .youtube: return "play.rectangle.fill"
        case .netflix: return "film.stack.fill"
        case .browser: return "globe"
        case .wikipedia: return "books.vertical.fill"
        case .twitch: return "video.fill"
        }
    }
    var startURL: URL {
        switch self {
        case .youtube: return URL(string: "https://m.youtube.com")!
        case .netflix: return URL(string: "https://www.netflix.com/br/")!
        case .browser: return URL(string: "https://www.google.com")!
        case .wikipedia: return URL(string: "https://pt.m.wikipedia.org")!
        case .twitch: return URL(string: "https://m.twitch.tv")!
        }
    }
    var description: String {
        switch self {
        case .youtube: return "Vídeos e pesquisas"
        case .netflix: return "Site da plataforma · DRM pode limitar reprodução"
        case .browser: return "Explore qualquer site HTTPS"
        case .wikipedia: return "Enciclopédia e curiosidades"
        case .twitch: return "Lives · player pode exigir Safari"
        }
    }
    var accent: Color {
        switch self {
        case .youtube: return Color(red: 0.97, green: 0.22, blue: 0.24)
        case .netflix: return Color(red: 0.84, green: 0.12, blue: 0.18)
        case .browser: return Color(red: 0.25, green: 0.67, blue: 1)
        case .wikipedia: return Color(red: 0.8, green: 0.8, blue: 0.86)
        case .twitch: return Color(red: 0.63, green: 0.38, blue: 1)
        }
    }
}

/// A single navigation session backs the two stereo web surfaces. WebKit
/// requires a UIView in each eye; only the left viewport drives navigation
/// and audio. The right is a muted, noninteractive visual companion.
@MainActor
final class VRWebSession: ObservableObject {
    let app: VRWebApp
    @Published private(set) var tabs: [VRBrowserTab] = []
    @Published private(set) var activeTabID = UUID()
    @Published private(set) var history: [URL] = []
    private let defaults: UserDefaults
    @Published var address: String
    @Published private(set) var requestedURL: URL
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published var loading = false
    @Published var message: String?
    @Published private(set) var pageZoom: CGFloat = 1.15
    @Published private(set) var favorites: [URL] = []

    private let favoritesKey = "vros.web.favorites.v1"
    var currentIsFavorite: Bool { favorites.contains(requestedURL) }

    weak var primary: WKWebView?
    weak var secondary: WKWebView?

    init(app: VRWebApp, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.app = app
        requestedURL = app.startURL
        address = app.startURL.absoluteString
        let tab = VRBrowserTab(url: app.startURL)
        tabs = [tab]
        activeTabID = tab.id
        history = (defaults.stringArray(forKey: "vros.web.history.v1") ?? []).compactMap(URL.init(string:))
            .filter { $0.scheme == "https" && $0.user == nil && $0.password == nil }
        favorites = Array((defaults.stringArray(forKey: favoritesKey) ?? [])
            .compactMap(URL.init(string:))
            .filter { $0.scheme == "https" }
            .suffix(4))
        message = app == .netflix
            ? "Filmes protegidos podem não tocar aqui. Use Safari se necessário."
            : nil
    }


    func newTab() {
        guard tabs.count < 8 else { message = "Limite de oito abas por janela"; return }
        saveActiveTab()
        let tab = VRBrowserTab(url: app.startURL)
        tabs.append(tab)
        selectTab(tab.id)
    }

    private func saveActiveTab() {
        if let index = tabs.firstIndex(where: { $0.id == activeTabID }) {
            tabs[index].url = requestedURL
        }
    }

    func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        saveActiveTab()
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        primary?.stopLoading()
        secondary?.stopLoading()
        primary = nil
        secondary = nil
        activeTabID = id
        requestedURL = tab.url
        address = tab.url.absoluteString
        canGoBack = false; canGoForward = false; loading = false
        message = nil
    }

    func nextTab() {
        guard let index = tabs.firstIndex(where: { $0.id == activeTabID }), !tabs.isEmpty else { return }
        selectTab(tabs[(index + 1) % tabs.count].id)
    }

    func closeActiveTab() {
        guard tabs.count > 1 else { goHome(); return }
        let old = activeTabID
        if let next = tabs.first(where: { $0.id != old }) { selectTab(next.id) }
        tabs.removeAll { $0.id == old }
    }

    func clearHistory() {
        history = []
        defaults.removeObject(forKey: "vros.web.history.v1")
    }

    func suspendMedia() {
        let script = "document.querySelectorAll('video,audio').forEach(el => el.pause())"
        primary?.evaluateJavaScript(script, completionHandler: nil)
        secondary?.evaluateJavaScript(script, completionHandler: nil)
    }

    func clearFavorites() {
        favorites.removeAll()
        defaults.removeObject(forKey: favoritesKey)
    }

    func navigate() {
        guard let url = VRBrowserURL.resolve(address) else {
            message = "Digite um endereço HTTPS válido ou uma pesquisa."
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
        // The secondary web view is a mirror, not an independent history.
        // Going back twice used to desynchronize the stereo eye histories.
        if primary?.canGoBack == true { primary?.goBack() }
    }

    func forward() {
        if primary?.canGoForward == true { primary?.goForward() }
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
            if let index = tabs.firstIndex(where: { $0.id == activeTabID }) { tabs[index].url = url }
            var recent = (defaults.stringArray(forKey: "vros.web.history.v1") ?? []).compactMap(URL.init(string:))
            recent.removeAll { $0 == url }
            recent.insert(url, at: 0)
            history = Array(recent.prefix(50))
            defaults.set(history.map(\.absoluteString), forKey: "vros.web.history.v1")
        }
    }

    func mirrorScroll(from offset: CGPoint) {
        guard let secondary = secondary else { return }
        let scroll = secondary.scrollView
        let insets = scroll.adjustedContentInset
        let maxY = max(-insets.top, scroll.contentSize.height -
                       scroll.bounds.height + insets.bottom)
        let y = min(maxY, max(-insets.top, offset.y))
        let maxX = max(0, scroll.contentSize.width - scroll.bounds.width)
        let x = min(maxX, max(0, offset.x))
        if abs(scroll.contentOffset.y - y) > 0.5 ||
           abs(scroll.contentOffset.x - x) > 0.5 {
            scroll.setContentOffset(CGPoint(x: x, y: y), animated: false)
        }
    }

    func toggleFavorite() {
        let url = primary?.url ?? requestedURL
        guard url.scheme == "https" else { return }
        if favorites.contains(url) {
            favorites.removeAll { $0 == url }
            message = "Favorito removido."
        } else {
            if favorites.count >= 4 { favorites.removeFirst() }
            favorites.append(url)
            message = "Página salva nos favoritos."
        }
        defaults.set(favorites.map(\.absoluteString),
                                  forKey: favoritesKey)
    }

    func openFavorite(_ index: Int) {
        guard favorites.indices.contains(index) else { return }
        let url = favorites[index]
        address = url.absoluteString
        message = nil
        requestedURL = url
    }

    func setPageZoom(_ zoom: CGFloat) {
        pageZoom = max(0.75, min(2.50, zoom))
        primary?.pageZoom = pageZoom
        secondary?.pageZoom = pageZoom
    }

    func adjustPageZoom(_ delta: CGFloat) {
        setPageZoom(pageZoom + delta)
    }

    func scrollByPage(_ direction: CGFloat) {
        guard let primary = primary else { return }
        let scroll = primary.scrollView
        scrollFromPinch(startY: scroll.contentOffset.y,
                        fingerDeltaY: -direction * scroll.bounds.height * 0.64)
    }

    func openInSafari() {
        guard let url = URL(string: address), url.scheme == "https" else {
            UIApplication.shared.open(requestedURL)
            return
        }
        UIApplication.shared.open(url)
    }

    /// Pinching over the web surface emulates a simple site click. WebKit does
    /// not expose a public API for trusted synthetic touch events, so protected
    /// video controls and some login widgets may still need physical touch.
    func tapFromPinch(x: CGFloat, y: CGFloat) {
        guard let primary = primary else { return }
        let px = min(0.99, max(0.01, x))
        let py = min(0.99, max(0.01, y))
        let js = """
        (() => {
          const x = Math.round(window.innerWidth * \(px));
          const y = Math.round(window.innerHeight * \(py));
          let target = document.elementFromPoint(x, y);
          if (!target) return false;
          const selectable = target.closest('a,button,input,textarea,select,[role="button"],[onclick]');
          if (selectable) target = selectable;
          if (target instanceof HTMLInputElement && target.type !== 'button') {
            target.focus();
          } else {
            target.click();
          }
          return true;
        })();
        """
        primary.evaluateJavaScript(js, completionHandler: nil)
    }

    /// A held pinch scrolls the primary web view. Existing KVO mirrors the
    /// resulting offset to the secondary, noninteractive stereo eye.
    func scrollFromPinch(startY: CGFloat, fingerDeltaY: CGFloat) {
        guard let primary = primary else { return }
        let scroll = primary.scrollView
        let minY = -scroll.adjustedContentInset.top
        let maxY = max(minY, scroll.contentSize.height -
                       scroll.bounds.height + scroll.adjustedContentInset.bottom)
        let newY = max(minY, min(maxY, startY - fingerDeltaY * 1.35))
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: newY),
                                animated: false)
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
                .forEach(el => {
                  try {
                    el.muted = true;
                    el.defaultMuted = true;
                    el.volume = 0;
                  } catch (_) {}
                });
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
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.isOpaque = false
        view.backgroundColor = UIColor.black
        view.scrollView.backgroundColor = UIColor.black
        view.pageZoom = session.pageZoom
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
        if abs(view.pageZoom - session.pageZoom) > 0.001 {
            view.pageZoom = session.pageZoom
        }
        guard context.coordinator.loadedURL != session.requestedURL else { return }
        context.coordinator.loadedURL = session.requestedURL
        if view.url != session.requestedURL {
            view.load(URLRequest(url: session.requestedURL))
        }
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        view.navigationDelegate = nil
        view.uiDelegate = nil
        view.loadHTMLString("", baseURL: nil)
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
            if rightEye {
                session.mirrorScroll(
                    from: session.primary?.scrollView.contentOffset ?? .zero)
            } else {
                session.didLoad(webView)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            guard !rightEye else { return }
            if (error as NSError).code == NSURLErrorCancelled { return }
            session.loading = false
            session.message = "Site indisponível: " + error.localizedDescription
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!,
                     withError error: Error) {
            guard !rightEye else { return }
            if (error as NSError).code == NSURLErrorCancelled { return }
            session.loading = false
            session.message = error.localizedDescription
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            if rightEye { webView.reload(); return }
            session.loading = false
            session.message = "O processo web foi encerrado. Use Recarregar ou Safari."
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
                navButton(session.currentIsFavorite ? "star.fill" : "star",
                          disabled: false) { session.toggleFavorite() }
                    .frame(width: 29)
                navButton("arrow.right", disabled: false) { session.navigate() }
                    .frame(width: 29)
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
                navButton("minus.magnifyingglass", disabled: false) {
                    session.adjustPageZoom(-0.15)
                }
                navButton("plus.magnifyingglass", disabled: false) {
                    session.adjustPageZoom(0.15)
                }
            }
            .frame(height: 28)
            HStack(spacing: 4) {
                navButton("arrow.up", disabled: false) { session.scrollByPage(-1) }
                Text("Página \(Int(session.pageZoom * 100))%")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity)
                if session.loading {
                    ProgressView().scaleEffect(0.7)
                }
                navButton("arrow.down", disabled: false) { session.scrollByPage(1) }
            }
            .frame(height: 25)
            if !session.favorites.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                    ForEach(Array(session.favorites.enumerated()), id: \.offset) { index, url in
                        Button {
                            session.openFavorite(index)
                        } label: {
                            Text(url.host?.replacingOccurrences(of: "www.", with: "")
                                 ?? "Favorito")
                                .font(.system(size: 9))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity)
                                .frame(height: 23)
                                .background(.white.opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(height: 24)
            }

            VRWebSurface(session: session, rightEye: rightEye)
                .id(session.activeTabID)
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
                     : "Pinça: clicar/rolar · setas: scroll · alça: mover")
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


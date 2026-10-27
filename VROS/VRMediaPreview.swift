import SwiftUI

enum VRMediaPreviewAction: Int, CaseIterable {
    case close, smaller, larger, rotate, reset, previous, next
}

/// Touch and Vision use these exact bounds, including gaps between controls.
enum VRMediaPreviewGeometry {
    static func content(_ size: CGSize) -> CGRect {
        CGRect(x: 10, y: 42, width: max(1, size.width - 20), height: max(1, size.height - 122))
    }
    static func rect(_ action: VRMediaPreviewAction, in size: CGSize) -> CGRect {
        if action == .close { return CGRect(x: size.width - 66, y: 6, width: 58, height: 30) }
        if action == .previous || action == .next {
            return CGRect(x: action == .previous ? 8 : size.width * 2 / 3,
                          y: size.height - 38, width: size.width / 3 - 8, height: 30)
        }
        let width = (size.width - 28) / 4
        return CGRect(x: 8 + CGFloat(action.rawValue - 1) * (width + 4),
                      y: size.height - 76, width: width, height: 30)
    }
    static func action(at point: CGPoint, in size: CGSize) -> VRMediaPreviewAction? {
        VRMediaPreviewAction.allCases.first { rect($0, in: size).contains(point) }
    }
}

extension VRMediaStore {
    func performPreview(_ action: VRMediaPreviewAction) {
        guard action == .close || !loadingPreview else { return }
        switch action {
        case .close: closePreview()
        case .smaller:
            if text != nil { adjustReaderSize(-2) } else { setZoom(zoom - 0.5) }
        case .larger:
            if text != nil { adjustReaderSize(2) } else { setZoom(zoom + 0.5) }
        case .rotate:
            if preview?.kind == .image { rotateImage() }
            else { changePage(-pdfPage) }
        case .reset:
            if text != nil { adjustReaderSize(12 - readerSize) } else { resetImage() }
        case .previous:
            if preview?.kind == .image { Task { await browsePhoto(-1) } } else { changePage(-1) }
        case .next:
            if preview?.kind == .image { Task { await browsePhoto(1) } } else { changePage(1) }
        }
    }
}

struct VRMediaPreview: View {
    @ObservedObject var store: VRMediaStore
    @State private var lastTranslation = CGSize.zero

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let content = VRMediaPreviewGeometry.content(size)
            ZStack(alignment: .topLeading) {
                Color(white: 0.06)
                Text(store.preview?.title ?? "Abrindo…")
                    .font(.system(size: 10, weight: .bold)).lineLimit(1)
                    .frame(width: max(1, size.width - 84), height: 30, alignment: .leading)
                    .position(x: (size.width - 84) / 2 + 10, y: 21)
                ZStack {
                    if store.loadingPreview { ProgressView() }
                    else if let image = store.image {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(width: content.width, height: content.height)
                            .rotationEffect(.degrees(Double(store.quarterTurns * 90)))
                            .scaleEffect(store.zoom).offset(store.pan)
                    } else {
                        Text(store.textPage).font(.system(size: CGFloat(store.readerSize)))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .frame(width: content.width, height: content.height).clipped()
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 3).onChanged { value in
                    let delta = CGSize(width: value.translation.width - lastTranslation.width,
                                       height: value.translation.height - lastTranslation.height)
                    store.moveImage(by: delta, viewport: content.size)
                    lastTranslation = value.translation
                }.onEnded { _ in lastTranslation = .zero })
                .position(x: content.midX, y: content.midY)
                ForEach(VRMediaPreviewAction.allCases, id: \.rawValue) { action in
                    let rect = VRMediaPreviewGeometry.rect(action, in: size)
                    Button { store.performPreview(action) } label: {
                        Text(label(action)).font(.system(size: 9, weight: .semibold))
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .frame(width: rect.width, height: rect.height)
                            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    }.position(x: rect.midX, y: rect.midY)
                }
                Text(store.preview?.kind == .image ? store.galleryPosition : "\(store.pdfPage + 1)/\(store.pageCount)")
                    .font(.system(size: 9)).frame(width: size.width / 3, height: 30)
                    .position(x: size.width / 2, y: size.height - 23)
            }.foregroundStyle(.white).buttonStyle(.plain)
                .onAppear { store.configureReadingViewport(content.size) }
                .onChange(of: content.size) { store.configureReadingViewport($0) }
        }
    }

    private func label(_ action: VRMediaPreviewAction) -> String {
        switch action {
        case .close: return "Fechar"
        case .smaller: return store.text != nil ? "A−" : "Zoom −"
        case .larger: return store.text != nil ? "A+" : "Zoom +"
        case .rotate: return store.preview?.kind == .image ? "Girar" : "Início"
        case .reset: return "Restaurar"
        case .previous: return "Anterior"
        case .next: return "Próxima"
        }
    }
}

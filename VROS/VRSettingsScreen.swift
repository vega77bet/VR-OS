import SwiftUI
import UIKit

/// The same settings screen is rendered in both VR lenses. All rows, toggles,
/// search and scroll offset use one session. Only LEFT UIKit table receives
/// direct touches so stereo surfaces cannot fight over scroll/navigation.
struct VRSettingsScreen: View {
    @ObservedObject var session: VRSettingsSession
    let rightEye: Bool
    let onClose: () -> Void

    @FocusState private var searchFocused: Bool
    static let toolbarHeight: CGFloat = 48
    static let searchHeight: CGFloat = 44

    var body: some View {
        VStack(spacing: 0) {
            navigationBar
                .frame(height: Self.toolbarHeight)
            if session.page == .home {
                searchBar
                    .frame(height: Self.searchHeight)
            }
            VRSettingsTable(session: session, rightEye: rightEye)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let notice = session.notice, !notice.isEmpty {
                Text(notice)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .foregroundStyle(.white.opacity(0.84))
                    .frame(maxWidth: .infinity)
                    .frame(height: 21)
                    .background(Color(white: 0.18))
                    .allowsHitTesting(false)
            }
        }
        .background(Color(white: 0.105))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .onChange(of: session.focusSearchRequest) { _ in
            if !rightEye && session.page == .home { searchFocused = true }
        }
        .onChange(of: session.page) { _ in searchFocused = false }
    }

    private var navigationBar: some View {
        HStack(spacing: 7) {
            if session.page != .home {
                Button { session.back() } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                        Text("Ajustes")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(white: 0.85))
                    .frame(minWidth: 61, alignment: .leading)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 1)
            Text(session.page.title)
                .font(.system(size: session.page == .home ? 21 : 14,
                              weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.66)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 1)
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(white: 0.64))
                    .frame(width: 28, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .background(Color(white: 0.15))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(white: 0.31)).frame(height: 0.5)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Color(white: 0.61))
            TextField("Buscar nos ajustes", text: $session.searchText)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($searchFocused)
                .disabled(rightEye)
                .submitLabel(.search)
                .lineLimit(1)
            if !session.searchText.isEmpty {
                Button {
                    session.searchText = ""
                    session.resetScroll()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(white: 0.62))
                }
                .buttonStyle(.plain)
                .disabled(rightEye)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 31)
        .background(Color(white: 0.19),
                    in: RoundedRectangle(cornerRadius: 9))
        .padding(.horizontal, 10)
        .frame(height: Self.searchHeight)
        .background(Color(white: 0.105))
    }
}

struct VRSettingsTable: UIViewRepresentable {
    @ObservedObject var session: VRSettingsSession
    let rightEye: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, rightEye: rightEye)
    }

    func makeUIView(context: Context) -> UITableView {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.backgroundColor = UIColor(white: 0.105, alpha: 1)
        table.separatorColor = UIColor(white: 0.27, alpha: 1)
        table.separatorInset = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 0)
        table.showsVerticalScrollIndicator = !rightEye
        table.keyboardDismissMode = .interactive
        table.isScrollEnabled = !rightEye
        table.isUserInteractionEnabled = !rightEye
        table.contentInsetAdjustmentBehavior = .never
        table.estimatedRowHeight = 0
        table.sectionHeaderHeight = 22
        table.estimatedSectionHeaderHeight = 0
        table.sectionFooterHeight = 8
        table.estimatedSectionFooterHeight = 0
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.register(VRSettingsTableCell.self,
                       forCellReuseIdentifier: "settings-row")
        if !rightEye { session.primaryTable = table }
        return table
    }

    func updateUIView(_ table: UITableView, context: Context) {
        let coordinator = context.coordinator
        let sections = session.sections
        // Never reload on every new scroll offset: doing that would interrupt
        // native inertia, destroy UIKit cells and desynchronize the two eyes.
        let identity = sections.flatMap { $0.rows }.map {
            "\($0.id):\(session.value(for: $0.id)):\(session.toggled($0.id)):\(session.selected($0.id))"
        }.joined(separator: "|")
        let signature = session.page.rawValue + "#" + session.searchText +
            "#" + identity + "#\(session.pendingConfirmation ?? "")"
        if coordinator.signature != signature {
            let pageChanged = coordinator.page != session.page
            coordinator.page = session.page
            coordinator.signature = signature
            coordinator.sections = sections
            table.reloadData()
            if pageChanged || coordinator.search != session.searchText {
                table.setContentOffset(.zero, animated: false)
            }
            coordinator.search = session.searchText
        }
        if rightEye {
            let maxScroll = max(0, table.contentSize.height - table.bounds.height)
            let desired = min(maxScroll, session.scrollOffset)
            if abs(table.contentOffset.y - desired) > 0.8 {
                table.setContentOffset(CGPoint(x: 0, y: desired), animated: false)
            }
        }
        if !rightEye && session.primaryTable !== table {
            session.primaryTable = table
        }
    }

    final class Coordinator: NSObject, UITableViewDelegate, UITableViewDataSource {
        let session: VRSettingsSession
        let rightEye: Bool
        var sections: [VRSettingsSection] = []
        var signature = ""
        var search = ""
        var page: VRSettingsPage = .home

        init(session: VRSettingsSession, rightEye: Bool) {
            self.session = session
            self.rightEye = rightEye
        }

        func numberOfSections(in tableView: UITableView) -> Int {
            sections.count
        }

        func tableView(_ tableView: UITableView,
                       numberOfRowsInSection section: Int) -> Int {
            sections[section].rows.count
        }

        func tableView(_ tableView: UITableView,
                       heightForRowAt indexPath: IndexPath) -> CGFloat {
            switch sections[indexPath.section].rows[indexPath.row].kind {
            case .slider: return 66
            case .navigate: return 56
            case .information: return 64
            default: return 55
            }
        }

        func tableView(_ tableView: UITableView,
                       heightForHeaderInSection section: Int) -> CGFloat {
            sections[section].title.isEmpty ? 12 : 29
        }

        func tableView(_ tableView: UITableView,
                       heightForFooterInSection section: Int) -> CGFloat {
            8
        }

        func tableView(_ tableView: UITableView,
                       viewForHeaderInSection section: Int) -> UIView? {
            let label = UILabel()
            label.text = sections[section].title
            label.textColor = UIColor(white: 0.62, alpha: 1)
            label.font = .systemFont(ofSize: 10, weight: .medium)
            let view = UIView()
            label.frame = CGRect(x: 12, y: 7, width: 300, height: 16)
            label.autoresizingMask = [.flexibleWidth]
            view.addSubview(label)
            return view
        }

        func tableView(_ tableView: UITableView,
                       cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let row = sections[indexPath.section].rows[indexPath.row]
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: "settings-row", for: indexPath)
                    as? VRSettingsTableCell else {
                return UITableViewCell()
            }
            cell.configure(row: row, session: session, enabled: !rightEye)
            return cell
        }

        func tableView(_ tableView: UITableView,
                       didSelectRowAt indexPath: IndexPath) {
            guard !rightEye else { return }
            tableView.deselectRow(at: indexPath, animated: false)
            let sections = self.sections
            guard indexPath.section < sections.count &&
                  indexPath.row < sections[indexPath.section].rows.count
            else { return }
            session.perform(sections[indexPath.section].rows[indexPath.row])
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !rightEye else { return }
            session.updateScroll(scrollView.contentOffset.y, fromPrimary: true)
        }
    }
}

/// Reusable UIKit cell, styled after grouped iOS Settings in charcoal gray.
/// Row selection handles navigation, toggles, choices and confirmation.
/// UISlider / +/- buttons are genuine interactive controls (primary eye).
final class VRSettingsTableCell: UITableViewCell {
    let slider = UISlider()
    private let iconBackground = UIView()
    private let glyph = UIImageView()
    private let headline = UILabel()
    private let detail = UILabel()
    private let chevron = UIImageView()
    private let checkmark = UIImageView()
    private let toggle = UISwitch()
    private let minus = UIButton(type: .system)
    private let plus = UIButton(type: .system)
    private let number = UILabel()
    private var row: VRSettingsRow?
    private weak var session: VRSettingsSession?
    private var controlEnabled = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = UIColor(white: 0.175, alpha: 1)
        contentView.backgroundColor = .clear
        selectedBackgroundView = UIView()
        selectedBackgroundView?.backgroundColor = UIColor(white: 0.27, alpha: 1)
        iconBackground.layer.cornerRadius = 6
        iconBackground.backgroundColor = UIColor(white: 0.40, alpha: 1)
        glyph.tintColor = .white
        glyph.contentMode = .scaleAspectFit
        headline.textColor = .white
        headline.font = .systemFont(ofSize: 11, weight: .medium)
        headline.adjustsFontSizeToFitWidth = true
        headline.minimumScaleFactor = 0.72
        headline.lineBreakMode = .byTruncatingTail
        detail.textColor = UIColor(white: 0.63, alpha: 1)
        detail.font = .systemFont(ofSize: 8.5)
        detail.lineBreakMode = .byTruncatingTail
        detail.adjustsFontSizeToFitWidth = true
        detail.minimumScaleFactor = 0.7
        chevron.image = UIImage(systemName: "chevron.right")
        chevron.tintColor = UIColor(white: 0.50, alpha: 1)
        checkmark.image = UIImage(systemName: "checkmark")
        checkmark.tintColor = UIColor(white: 0.85, alpha: 1)
        toggle.onTintColor = UIColor(white: 0.68, alpha: 1)
        toggle.transform = CGAffineTransform(scaleX: 0.75, y: 0.75)
        toggle.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
        slider.minimumTrackTintColor = UIColor(white: 0.82, alpha: 1)
        slider.maximumTrackTintColor = UIColor(white: 0.32, alpha: 1)
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        for (button, symbol) in [(minus, "minus"), (plus, "plus")] {
            button.setImage(UIImage(systemName: symbol), for: .normal)
            button.tintColor = .white
            button.backgroundColor = UIColor(white: 0.29, alpha: 1)
            button.layer.cornerRadius = 5
        }
        minus.addTarget(self, action: #selector(minusPressed), for: .touchUpInside)
        plus.addTarget(self, action: #selector(plusPressed), for: .touchUpInside)
        number.textColor = .white
        number.textAlignment = .center
        number.font = .monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        number.adjustsFontSizeToFitWidth = true
        number.minimumScaleFactor = 0.7
        for view in [iconBackground, glyph, headline, detail, chevron,
                     checkmark, toggle, minus, plus, number, slider] {
            contentView.addSubview(view)
        }
        accessibilityTraits.insert(.button)
    }

    required init?(coder: NSCoder) { nil }

    func configure(row: VRSettingsRow, session: VRSettingsSession,
                   enabled: Bool) {
        self.row = row
        self.session = session
        self.controlEnabled = enabled
        headline.text = row.title
        detail.text = row.subtitle
        glyph.image = UIImage(systemName: row.symbol.isEmpty
                              ? "gearshape" : row.symbol)
        let iconPresent = !row.symbol.isEmpty
        iconBackground.isHidden = !iconPresent
        glyph.isHidden = !iconPresent
        if case let .navigate(page) = row.kind {
            iconBackground.backgroundColor =
                UIColor(white: page.symbolGray, alpha: 1)
        } else {
            iconBackground.backgroundColor = UIColor(white: 0.40, alpha: 1)
        }
        chevron.isHidden = true
        checkmark.isHidden = true
        toggle.isHidden = true
        minus.isHidden = true
        plus.isHidden = true
        number.isHidden = true
        slider.isHidden = true
        switch row.kind {
        case .navigate:
            chevron.isHidden = false
        case .choice:
            checkmark.isHidden = !session.selected(row.id)
        case .toggle:
            toggle.isHidden = false
            toggle.isOn = session.toggled(row.id)
            toggle.isEnabled = enabled
        case .stepper:
            minus.isHidden = false
            plus.isHidden = false
            number.isHidden = false
            minus.isEnabled = enabled
            plus.isEnabled = enabled
            number.text = session.value(for: row.id)
        case .slider:
            slider.isHidden = false
            slider.value = Float(session.normalized(row.id))
            slider.isEnabled = enabled
            number.isHidden = false
            number.text = session.value(for: row.id)
        case .information, .action:
            break
        }
        isUserInteractionEnabled = enabled
        accessibilityLabel = row.title + (row.subtitle.isEmpty
                                            ? "" : ", " + row.subtitle)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let row = row else { return }
        let w = contentView.bounds.width
        let h = contentView.bounds.height
        let hasIcon = !row.symbol.isEmpty
        iconBackground.frame = CGRect(x: 9, y: (h - 25) / 2,
                                      width: 25, height: 25)
        glyph.frame = iconBackground.frame.insetBy(dx: 5, dy: 5)
        let x: CGFloat = hasIcon ? 42 : 13
        var right: CGFloat = w - 13
        switch row.kind {
        case .navigate:
            chevron.frame = CGRect(x: w - 20, y: (h - 13) / 2,
                                   width: 9, height: 13)
            right = w - 29
        case .choice:
            checkmark.frame = CGRect(x: w - 29, y: (h - 16) / 2,
                                     width: 18, height: 16)
            right = w - 36
        case .toggle:
            toggle.frame = CGRect(x: w - 57, y: (h - 31) / 2,
                                  width: 51, height: 31)
            right = w - 61
        case .stepper:
            let controlsLeft = max(x + 50, w - 100)
            minus.frame = CGRect(x: controlsLeft, y: (h - 24) / 2,
                                 width: 23, height: 24)
            number.frame = CGRect(x: controlsLeft + 25,
                                  y: (h - 24) / 2, width: 37, height: 24)
            plus.frame = CGRect(x: controlsLeft + 64,
                                y: (h - 24) / 2, width: 23, height: 24)
            right = controlsLeft - 5
        case .slider:
            slider.frame = CGRect(x: max(x + 55, w - 124),
                                  y: (h - 28) / 2 + 7, width: 105, height: 28)
            number.frame = CGRect(x: w - 75, y: 1, width: 59, height: 17)
            right = w - 126
        case .information, .action:
            break
        }
        let width = max(32, right - x)
        headline.frame = CGRect(x: x, y: h / 2 - 17,
                                 width: width, height: 17)
        detail.frame = CGRect(x: x, y: h / 2 + 1,
                               width: width, height: 15)
    }

    @objc private func toggleChanged() {
        guard controlEnabled, let row = row else { return }
        session?.perform(row)
    }
    @objc private func sliderChanged() {
        guard controlEnabled, let row = row else { return }
        session?.setNormalized(row.id, fraction: CGFloat(slider.value))
    }
    @objc private func minusPressed() {
        guard controlEnabled, let row = row else { return }
        session?.perform(row, direction: -1)
    }
    @objc private func plusPressed() {
        guard controlEnabled, let row = row else { return }
        session?.perform(row, direction: 1)
    }
}

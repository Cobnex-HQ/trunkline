import UIKit
import SwiftUI
#if canImport(TrunklineCore)
import TrunklineCore
#endif

struct TerminalSessionsList: UIViewControllerRepresentable {
    @ObservedObject var model: ConnectionModel
    func makeUIViewController(context: Context) -> TerminalSessionsController { TerminalSessionsController() }
    func updateUIViewController(_ controller: TerminalSessionsController, context: Context) {
        controller.onOpen = { model.selectedTerminalID = $0 }
        controller.onEnd = { model.closeTerminal($0) }
        controller.onRefresh = { model.send(.listTerminals) }
        controller.update(sessions: model.sessions, pending: model.closingTerminalIDs, loaded: model.hasLoadedTerminals)
    }
}

/// UIKit owns row sizing, VoiceOver, refresh, swipe actions and iPad popovers.
final class TerminalSessionsController: UITableViewController {
    enum Section: Int { case running, ended }
    private final class Source: UITableViewDiffableDataSource<Section, UUID> {
        override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
            let snapshot = snapshot()
            let id = snapshot.sectionIdentifiers[section]
            return "\(id == .running ? "Running sessions" : "Ended sessions") (\(snapshot.numberOfItems(inSection: id)))"
        }
        override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
            section == 0 ? "Only sessions started in Trunkline are listed. Disconnecting keeps them running." : nil
        }
    }
    var onOpen: ((UUID) -> Void)?
    var onEnd: ((UUID) -> Void)?
    var onRefresh: (() -> Void)?
    private var sessions: [TerminalSessionInfo] = []
    private var pending: Set<UUID> = []
    private var source: Source!

    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("Use init()") }
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "session")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 70
        tableView.alwaysBounceVertical = true
        tableView.tintColor = UIColor(named: "AccentColor")
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refreshSessions), for: .valueChanged)
        source = Source(tableView: tableView) { [weak self] table, indexPath, id in
            guard let self, let session = self.sessions.first(where: { $0.id == id }) else { return nil }
            let cell = table.dequeueReusableCell(withIdentifier: "session", for: indexPath)
            let ending = self.isPending(session)
            let status = ending ? (session.isRunning ? "Ending…" : "Removing…") : session.statusTitle
            var content = cell.defaultContentConfiguration()
            content.text = session.title
            content.secondaryText = "\(session.kind.title) · \(status)"
            content.textProperties.numberOfLines = 0
            content.secondaryTextProperties.numberOfLines = 0
            content.secondaryTextProperties.color = .secondaryLabel
            content.image = UIImage(systemName: session.isRunning ? "terminal" : "clock")
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            cell.accessoryView = nil
            if ending {
                let spinner = UIActivityIndicatorView(style: .medium)
                spinner.startAnimating()
                cell.accessoryView = spinner
            }
            cell.accessibilityLabel = "\(session.title), \(session.kind.title), \(status)"
            cell.accessibilityHint = session.isRunning ? "Open terminal session" : "Read saved output"
            return cell
        }
    }
    func update(sessions: [TerminalSessionInfo], pending: Set<UUID>, loaded: Bool) {
        loadViewIfNeeded()
        refreshControl?.endRefreshing()
        self.sessions = sessions
        self.pending = pending
        var snapshot = NSDiffableDataSourceSnapshot<Section, UUID>()
        let running = sessions.filter(\.isRunning)
        let ended = sessions.filter { !$0.isRunning }
        if !running.isEmpty { snapshot.appendSections([.running]); snapshot.appendItems(running.map(\.id), toSection: .running) }
        if !ended.isEmpty { snapshot.appendSections([.ended]); snapshot.appendItems(ended.map(\.id), toSection: .ended) }
        let previous = Set(source.snapshot().itemIdentifiers)
        snapshot.reconfigureItems(snapshot.itemIdentifiers.filter { previous.contains($0) })
        source.apply(snapshot, animatingDifferences: view.window != nil && !UIAccessibility.isReduceMotionEnabled)
        if sessions.isEmpty {
            let title = UILabel()
            title.text = loaded ? "No terminal sessions" : "Loading sessions…"
            title.font = .preferredFont(forTextStyle: .headline)
            title.adjustsFontForContentSizeCategory = true
            title.numberOfLines = 0
            let detail = UILabel()
            detail.text = loaded ? "Use + to start a session on your Mac." : "Pull down or tap Refresh to try again."
            detail.font = .preferredFont(forTextStyle: .subheadline)
            detail.adjustsFontForContentSizeCategory = true
            detail.textColor = .secondaryLabel
            detail.numberOfLines = 0
            var config = UIButton.Configuration.tinted()
            config.title = "Refresh"
            let refresh = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in self?.onRefresh?() })
            let stack = UIStackView(arrangedSubviews: [title, detail, refresh])
            stack.axis = .vertical
            stack.alignment = .center
            stack.spacing = 12
            let background = UIView()
            background.addSubview(stack)
            stack.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: background.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: background.centerYAnchor),
                stack.leadingAnchor.constraint(greaterThanOrEqualTo: background.leadingAnchor, constant: 24),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: background.trailingAnchor, constant: -24)
            ])
            tableView.backgroundView = background
        } else { tableView.backgroundView = nil }
    }
    @objc private func refreshSessions() { onRefresh?() }
    private func isPending(_ session: TerminalSessionInfo) -> Bool { pending.contains(session.id) || session.isStopping == true }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if let id = source.itemIdentifier(for: indexPath) { onOpen?(id) }
    }
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let id = source.itemIdentifier(for: indexPath), let session = sessions.first(where: { $0.id == id }), !isPending(session) else { return nil }
        let action = UIContextualAction(style: .destructive, title: session.isRunning ? "End" : "Remove") { [weak self] _, _, completion in
            self?.confirmEnd(session)
            completion(true)
        }
        let configuration = UISwipeActionsConfiguration(actions: [action])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }
    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let id = source.itemIdentifier(for: indexPath), let session = sessions.first(where: { $0.id == id }), !isPending(session) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [UIAction(title: session.isRunning ? "End session" : "Remove history", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in self?.confirmEnd(session) }])
        }
    }
    private func confirmEnd(_ session: TerminalSessionInfo) {
        guard presentedViewController == nil, !isPending(session) else { return }
        let alert = UIAlertController(title: session.isRunning ? "End \(session.title)?" : "Remove \(session.title)?",
            message: session.isRunning ? "Stops this shell and processes attached to its terminal. Other sessions keep running." : "Removes this session’s saved output from the Mac.", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: session.isRunning ? "End session" : "Remove history", style: .destructive) { [weak self] _ in self?.onEnd?(session.id) })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = tableView
            popover.sourceRect = source.indexPath(for: session.id).map(tableView.rectForRow(at:)) ?? tableView.bounds
        }
        present(alert, animated: true)
    }
}

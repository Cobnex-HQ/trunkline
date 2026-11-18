#if canImport(TrunklineCore)
import TrunklineCore
#endif
import Foundation
import Combine

@MainActor
final class ClientControls: ObservableObject {
    @Published private(set) var snapshot: MacControlSnapshot?
    @Published private(set) var pending: UUID?
    @Published var error: String?
    @Published private(set) var refreshError: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isUserRefreshing = false
    @Published private(set) var selectedWindowAppPID: Int32?
    var send: ((WireMessage) -> Void)?
    private var timeout: Task<Void, Never>?
    private var refreshTimeout: Task<Void, Never>?
    private var refreshID: UUID?
    private var queuedWindowRefresh = false
    private var expandedWindowList = false
    var hasCurrentWindowList: Bool {
        guard let snapshot else { return false }
        return snapshot.windowScope?.requestedPID == selectedWindowAppPID
    }
    func selectWindowApplication(_ pid: Int32?) {
        guard snapshot?.windowScope != nil, pid != selectedWindowAppPID else { return }
        if let pid, snapshot?.apps.contains(where: { $0.pid == pid && pid > 0 }) != true {
            error = "This app has closed. Refresh the app list."; return
        }
        selectedWindowAppPID = pid; expandedWindowList = false
        if isRefreshing { queuedWindowRefresh = true }
        else { refresh() }
    }
    func refresh(automatically: Bool = false) {
        guard !isRefreshing else { return }
        if !automatically { expandedWindowList = false }
        beginRefresh(preserveWindows: automatically && expandedWindowList, automatically: automatically)
    }
    func loadMoreWindows() {
        guard !isRefreshing, hasCurrentWindowList, let cursor = snapshot?.windowPage?.nextCursor else { return }
        expandedWindowList = true
        beginRefresh(windowCursor: cursor)
    }
    func refreshAndWait() async {
        refresh()
        for await refreshing in $isRefreshing.values {
            if !refreshing || Task.isCancelled { return }
        }
    }
    private func beginRefresh(windowCursor: UUID? = nil, preserveWindows: Bool = false, automatically: Bool = false) {
        let id = UUID(); refreshID = id; isRefreshing = true
        isUserRefreshing = !automatically
        refreshTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            guard let self, self.refreshID == id else { return }
            self.isRefreshing = false; self.isUserRefreshing = false; self.refreshTimeout = nil; self.refreshID = nil
            self.refreshError = "The Mac isn’t responding. Try refreshing."
            if self.queuedWindowRefresh { self.queuedWindowRefresh = false; self.refresh() }
        }
        send?(.requestControls(windowAppPID: selectedWindowAppPID, requestID: id, windowCursor: windowCursor, preserveWindows: preserveWindows ? true : nil))
    }
    func perform(_ action: MacControlAction, confirmed: Bool = false) {
        guard pending == nil else { return }
        if case .keepAwake = action {
            guard let awake = snapshot?.keepAwake, !awake.requiresLocalChange else {
                error = "Keep-awake controls are unavailable. Update the Mac app or check its Power settings."
                return
            }
        }
        guard !action.requiresConfirmation || confirmed else {
            error = "Confirm this action before continuing."; return
        }
        if case let .power(action) = action, snapshot?.power?.availableActions.contains(action) != true {
            error = "This power control isn’t available. Refresh the Mac’s controls."; return
        }
        if case let .desktopDisplay(id) = action {
            guard let selection = snapshot?.desktopDisplays, selection.isAvailable else {
                error = "Display switching isn’t available on this Mac."; return
            }
            guard selection.displays.contains(where: { $0.id == id }) else {
                error = MacControlError.missingDisplay.localizedDescription; return
            }
        }
        if case let .moveWindow(id, displayID) = action {
            guard hasCurrentWindowList, snapshot?.accessibility == true,
                  snapshot?.windows.contains(where: { $0.id == id && $0.canMoveToDisplay == true }) == true else {
                error = "This window can’t move to another display. Refresh the window list."; return
            }
            guard snapshot?.displays.contains(where: { $0.id == displayID }) == true else {
                error = MacControlError.missingDisplay.localizedDescription; return
            }
        }
        do { try action.validate() } catch { self.error = error.localizedDescription; return }
        let request = MacControlRequest(action: action)
        pending = request.id; error = nil
        timeout?.cancel()
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            guard let self, self.pending == request.id else { return }
            self.pending = nil; self.error = "The Mac didn’t confirm this action. Refresh before trying again."
        }
        send?(.control(request))
    }
    func handle(_ message: WireMessage) -> Bool {
        switch message {
        case let .controls(snapshot):
            if let id = snapshot.requestID, id != refreshID { return true }
            // A new host must correlate its replies. Old hosts omit both fields.
            if refreshID != nil, snapshot.requestID == nil, snapshot.windowScope != nil { return true }
            refreshTimeout?.cancel(); refreshTimeout = nil
            isRefreshing = false; isUserRefreshing = false; refreshError = nil; refreshID = nil
            if snapshot.windowScope == nil { selectedWindowAppPID = nil }
            if snapshot.windowPage == nil || self.snapshot?.windowScope?.application?.pid != snapshot.windowScope?.application?.pid {
                expandedWindowList = false
            }
            // Correlation metadata must not redraw an otherwise unchanged screen.
            var presented = snapshot; presented.requestID = nil
            if self.snapshot != presented { self.snapshot = presented }
            let shouldRefresh = queuedWindowRefresh && !hasCurrentWindowList
            queuedWindowRefresh = false
            if shouldRefresh { refresh() }
            return true
        case let .controlResult(result):
            guard result.id == pending else { return true }
            timeout?.cancel(); timeout = nil; pending = nil; error = result.error
            refresh(); return true
        default: return false
        }
    }
    func reset() {
        timeout?.cancel(); timeout = nil
        refreshTimeout?.cancel(); refreshTimeout = nil
        isRefreshing = false; isUserRefreshing = false; refreshError = nil
        refreshID = nil; selectedWindowAppPID = nil; queuedWindowRefresh = false; expandedWindowList = false
        pending = nil; snapshot = nil; error = nil
    }
}

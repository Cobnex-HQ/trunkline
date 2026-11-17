#if canImport(TrunklineCore)
import TrunklineCore
#endif
import SwiftUI

struct SessionsView: View {
    @ObservedObject var model: ConnectionModel
    private var path: Binding<[UUID]> {
        Binding(get: { model.selectedTerminalID.map { [$0] } ?? [] },
                set: { model.selectedTerminalID = $0.last })
    }
    var body: some View {
        NavigationStack(path: path) {
            List {
                Section("Sessions") {
                    ForEach(model.sessions) { session in
                        NavigationLink(value: session.id) {
                            HStack(spacing: 12) {
                                Image(systemName: "terminal").foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.title).font(.subheadline.weight(.medium))
                                    Text(session.isRunning ? session.kind.title + " · Running" : "Session ended")
                                        .font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, 2)
                            }
                        }
                            .accessibilityLabel("Open \(session.title)")
                    }
                    if !model.hasLoadedTerminals {
                        HStack(spacing: 12) { ProgressView(); Text("Loading sessions…") }
                        Button("Refresh", systemImage: "arrow.clockwise") { model.send(.listTerminals) }
                    } else if model.sessions.isEmpty {
                        if model.isCreatingTerminal {
                            HStack(spacing: 12) { ProgressView(); Text("Starting session…") }
                        } else {
                            ContentUnavailableView("No sessions", systemImage: "terminal", description: Text("Run commands on your Mac."))
                            newSessionMenu
                        }
                    }
                }
            }
            .nativeWorkspaceStyle()
            .listStyle(.insetGrouped)
            .frame(maxWidth: 840).frame(maxWidth: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Terminal")
            .toolbar {
                if model.hasLoadedTerminals && !model.sessions.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        if model.isCreatingTerminal { ProgressView().accessibilityLabel("Starting terminal session") }
                        else { newSessionMenu }
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let session = model.sessions.first(where: { $0.id == id }) {
                    SessionDetail(model: model, session: session).id(id)
                } else {
                    ContentUnavailableView("Session ended", systemImage: "terminal")
                }
            }
        }
        .onAppear { model.send(.listTerminals) }
    }
    private var newSessionMenu: some View {
        Menu {
            ForEach(TerminalKind.allCases) { kind in
                Button(kind.title) { model.createTerminal(kind) }
            }
        } label: { Label("New session", systemImage: "plus") }
            .accessibilityLabel("Start a terminal session")
            .disabled(!model.hasLoadedTerminals || model.isCreatingTerminal)
    }
}

struct SessionDetail: View {
    @ObservedObject var model: ConnectionModel
    let session: TerminalSessionInfo
    @State private var keyboard = false
    @State private var confirmClose = false
    @State private var paste = ""
    @State private var showPaste = false
    @State private var renaming = false
    @State private var sessionName = ""
    @State private var input = TerminalShortcutInput()
    @ScaledMetric(relativeTo: .subheadline) private var terminalFontSize: CGFloat = 14
    var body: some View {
        VStack(spacing: 0) {
            if !session.isRunning {
                HStack {
                    Text("Session ended").foregroundStyle(.secondary)
                    Spacer()
                    Button("New session") { model.createTerminal(session.kind) }.disabled(model.isCreatingTerminal)
                }.font(.subheadline).padding(12).background(.bar)
            }
            TerminalSurface(model: model, sessionID: session.id, showKeyboard: $keyboard, fontSize: terminalFontSize, input: input, acceptsInput: session.isRunning)
                .background(.black)
            if !keyboard { ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button("Scroll history up", systemImage: "chevron.up") { input.terminal?.pageHistory(up: true) }
                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                    Button("Scroll history down", systemImage: "chevron.down") { input.terminal?.pageHistory(up: false) }
                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                    Button("Latest output", systemImage: "arrow.down.to.line") { input.terminal?.jumpToLatest() }
                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                    if session.isRunning {
                    ForEach(TerminalShortcut.allCases, id: \.self) { terminalKey($0) }
                    }
                }.padding(.horizontal, 12).padding(.vertical, 8)
            }.background(.bar) }
        }
        .navigationTitle(session.title).navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(keyboard ? "Hide keyboard" : "Show keyboard", systemImage: "keyboard") { keyboard.toggle() }.labelStyle(.iconOnly).disabled(!session.isRunning)
                Menu {
                    Button("Page up", systemImage: "chevron.up") { input.terminal?.pageHistory(up: true) }
                    Button("Page down", systemImage: "chevron.down") { input.terminal?.pageHistory(up: false) }
                    Button("Latest output", systemImage: "arrow.down.to.line") { input.terminal?.jumpToLatest() }
                    Divider()
                    Button("Rename", systemImage: "pencil") { sessionName = session.title; renaming = true }
                    Button("Paste text…", systemImage: "doc.on.clipboard") { showPaste = true }.disabled(!session.isRunning)
                    if session.isRunning {
                        Button("End session", systemImage: "stop.circle", role: .destructive) { confirmClose = true }
                    } else {
                        Button("Remove session", systemImage: "trash", role: .destructive) { model.send(.closeTerminal(id: session.id)); model.selectedTerminalID = nil }
                    }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Session controls")
            }
        }
        .alert("Rename session", isPresented: $renaming) {
            TextField("Name", text: $sessionName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { model.send(.renameTerminal(id: session.id, title: sessionName)) }
                .disabled(sessionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sessionName.count > 80)
        }
        .confirmationDialog("End this terminal session?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("End session", role: .destructive) { model.send(.closeTerminal(id: session.id)); model.selectedTerminalID = nil }
        } message: { Text("This stops the shell and its foreground command on your Mac. Disconnecting keeps them running.") }
        .sheet(isPresented: $showPaste) {
            NavigationStack {
                Form {
                    TextEditor(text: $paste).font(.system(.body, design: .monospaced)).frame(minHeight: 200)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    PasteButton(payloadType: String.self) { paste = $0.joined(separator: "\n") }
                    Text("Text is sent as bracketed paste. How it is handled depends on the application running in this session.").font(.caption).foregroundStyle(.secondary)
                }.navigationTitle("Paste into session")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showPaste = false; paste = "" } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Paste") {
                                model.sendTerminalPaste(paste, id: session.id)
                                showPaste = false; paste = ""
                            }.disabled(paste.isEmpty || paste.utf8.count > 65536)
                        }
                    }
            }
        }
    }
    private func terminalKey(_ key: TerminalShortcut) -> some View {
        Button { input.send(key) } label: {
            Text(key.title).font(.system(.subheadline, design: .monospaced))
                .frame(minWidth: 44, minHeight: 44)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(TerminalKeyStyle())
        .accessibilityLabel(key.accessibilityLabel)
    }
}

private struct TerminalKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.tint)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}


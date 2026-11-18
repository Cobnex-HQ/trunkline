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
            TerminalSessionsList(model: model)
            .nativeWorkspaceStyle()
            .frame(maxWidth: 840).frame(maxWidth: .infinity)
            .background(Color.workspaceBackground)
            .navigationTitle("Terminal")
            .toolbar {
                if model.hasLoadedTerminals {
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
    @Environment(\.verticalSizeClass) private var verticalSizeClass
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
            if model.isEndingTerminal(session.id) {
                HStack(spacing: 8) { ProgressView(); Text(session.isRunning ? "Ending session…" : "Removing history…") }
                    .font(.subheadline).padding(12).frame(maxWidth: .infinity).background(.bar)
            }
            if !session.isRunning {
                HStack {
                    Text("Session ended").foregroundStyle(.secondary)
                    Spacer()
                    Button("New session") { model.createTerminal(session.kind) }.disabled(model.isCreatingTerminal)
                }.font(.subheadline).padding(12).background(.bar)
            }
            TerminalSurface(model: model, sessionID: session.id, showKeyboard: $keyboard, fontSize: terminalFontSize, input: input, acceptsInput: session.isRunning && !model.isEndingTerminal(session.id))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
            if !keyboard { ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if session.isRunning && !model.isEndingTerminal(session.id) {
                        ForEach(TerminalShortcut.allCases, id: \.self) { terminalKey($0) }
                    }
                    Menu {
                        Button("Page up", systemImage: "chevron.up") { input.terminal?.pageHistory(up: true) }
                        Button("Page down", systemImage: "chevron.down") { input.terminal?.pageHistory(up: false) }
                        Button("Latest output", systemImage: "arrow.down.to.line") { input.terminal?.jumpToLatest() }
                    } label: { Label("History", systemImage: "clock.arrow.circlepath").padding(.horizontal, 8).frame(minHeight: 44) }
                    .buttonStyle(TerminalKeyStyle())
                }.padding(.horizontal).padding(.vertical, 4)
            }.background(.bar) }
        }
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle(session.title).navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(keyboard ? "Hide keyboard" : "Show keyboard", systemImage: "keyboard") { keyboard.toggle() }.labelStyle(.iconOnly).disabled(!session.isRunning || model.isEndingTerminal(session.id))
                Menu {
                    Button("Page up", systemImage: "chevron.up") { input.terminal?.pageHistory(up: true) }
                    Button("Page down", systemImage: "chevron.down") { input.terminal?.pageHistory(up: false) }
                    Button("Latest output", systemImage: "arrow.down.to.line") { input.terminal?.jumpToLatest() }
                    Divider()
                    Button("Rename", systemImage: "pencil") { sessionName = session.title; renaming = true }
                    Button("Paste text…", systemImage: "doc.on.clipboard") { showPaste = true }.disabled(!session.isRunning || model.isEndingTerminal(session.id))
                    if session.isRunning {
                        Button("End session", systemImage: "stop.circle", role: .destructive) { confirmClose = true }.disabled(model.isEndingTerminal(session.id))
                    } else {
                        Button("Remove session", systemImage: "trash", role: .destructive) { model.closeTerminal(session.id) }.disabled(model.isEndingTerminal(session.id))
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
            Button("End session", role: .destructive) { model.closeTerminal(session.id) }
        } message: { Text("This stops the shell and processes attached to its terminal on your Mac. Other sessions keep running.") }
        .sheet(isPresented: $showPaste) {
            NavigationStack {
                Form {
                    TrunklineSection {
                        TextEditor(text: $paste).font(.system(.body, design: .monospaced)).frame(minHeight: verticalSizeClass == .compact ? 96 : 180)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityLabel("Text to paste")
                        PasteButton(payloadType: String.self) { paste = $0.joined(separator: "\n") }
                    } footer: {
                        Text("Text is sent as bracketed paste. How it is handled depends on the application running in this session.")
                    }
                }.nativeWorkspaceStyle().navigationTitle("Paste into session")
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
            .background(.quaternary, in: TrunklineControls.shape)
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}


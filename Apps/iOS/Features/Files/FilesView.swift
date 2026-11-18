#if canImport(TrunklineCore)
import TrunklineCore
#endif
import SwiftUI
import UniformTypeIdentifiers

struct FilesView: View {
    @ObservedObject var files: ClientFiles
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var showImporter = false
    @State private var showDisconnectConfirmation = false
    @State private var renameTarget: RemoteFile?
    @State private var trashTarget: RemoteFile?
    @State private var editingName = false
    @State private var newName = ""
    @State private var search = ""
    @State private var sortOrder = FileSortOrder.name
    @State private var visibleFiles: [RemoteFile] = []
    private enum FileSortOrder: String, CaseIterable, Identifiable {
        case name = "Name", size = "Size (largest first)"
        var id: Self { self }
    }
    private func updateListing() {
        // Transfer progress must not repeatedly filter and sort an unchanged folder.
        visibleFiles = files.entries.filter { search.isEmpty || $0.name.localizedStandardContains(search) }.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            if sortOrder == .size, !lhs.isDirectory, lhs.size != rhs.size { return lhs.size > rhs.size }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
    private var updateNotice: String? {
        switch (files.features.contains(.mutations), files.features.contains(.folderUpload)) {
        case (true, true): nil
        case (true, false): "Update Trunkline on your Mac to upload into folders."
        case (false, true): "Update Trunkline on your Mac to create folders, rename files and use Trash."
        case (false, false): "Update Trunkline on your Mac to create folders, rename files, use Trash and upload into folders."
        }
    }
    var body: some View {
        NavigationStack {
            List {
                if let name = files.transferName {
                    Section("Transferring") {
                        Text(name).font(.subheadline.weight(.medium)).lineLimit(textSize.isAccessibilitySize ? nil : 2)
                        ProgressView(value: files.progress)
                        let statusLayout = textSize.isAccessibilitySize
                                ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout())
                            statusLayout {
                            Text(files.isCancelling ? "Cancelling…" : "\(Int(files.progress * 100))% · Keep Trunkline open")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if !textSize.isAccessibilitySize { Spacer() }
                            if files.features.contains(.cancellation) {
                                Button("Cancel", role: .cancel) { files.cancelTransfer() }.frame(minHeight: 44).disabled(files.isCancelling)
                            } else {
                                Button("Disconnect to cancel") { showDisconnectConfirmation = true }.frame(minHeight: 44)
                            }
                        }
                    }
                }
                if files.requiresReconnect {
                    Section {
                        Text(files.error ?? "Reconnect to continue.").foregroundStyle(.secondary)
                        Button("Disconnect", systemImage: "power") { showDisconnectConfirmation = true }
                    }
                }
                if let url = files.downloadedURL {
                    Section("Downloaded") {
                        ShareLink(item: url) { Label("Save or share \(url.lastPathComponent)", systemImage: "square.and.arrow.up") }
                    }
                }
                Section {
                    if !files.path.isEmpty { Button("Parent folder", systemImage: "arrow.turn.up.left") { files.parent() }.disabled(files.isBusy) }
                    if files.isLoading && !files.hasLoadedListing && files.entries.isEmpty { HStack(spacing: 12) { GlacierLoadingIndicator(); Text("Loading folder…") } }
                    else if files.entries.isEmpty {
                        ContentUnavailableView("No files here", systemImage: "folder", description: Text("Upload a file or select a shared folder on your Mac."))
                    } else if visibleFiles.isEmpty {
                        ContentUnavailableView.search(text: search)
                    }
                    ForEach(visibleFiles) { file in
                        HStack(spacing: 8) {
                            Button {
                                if file.isDirectory { files.list(file.path) } else { files.download(file) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: file.isDirectory ? "folder.fill" : "doc").foregroundStyle(.tint).frame(width: 28)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(file.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                            .lineLimit(textSize.isAccessibilitySize ? nil : 2)
                                        if !file.isDirectory { Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)).font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Spacer(minLength: 4)
                                    Image(systemName: file.isDirectory ? "chevron.right" : "arrow.down.circle").foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .accessibilityLabel(file.isDirectory ? "Open \(file.name)" : "Download \(file.name)")
                                .accessibilityValue(file.isDirectory ? "Folder" : ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                            if files.features.contains(.mutations) {
                                Menu { fileActions(file) } label: {
                                    Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
                                }.buttonStyle(.borderless).accessibilityLabel("Actions for \(file.name)")
                                    .confirmationDialog("Move to Trash?", isPresented: Binding(
                                        get: { trashTarget?.id == file.id },
                                        set: { if !$0 && trashTarget?.id == file.id { trashTarget = nil } }
                                    ), titleVisibility: .visible) {
                                        Button("Move to Trash", role: .destructive) {
                                            files.mutate(.trash(path: file.path)); trashTarget = nil
                                        }
                                    } message: { Text(file.name) }
                            }
                        }
                        .disabled(files.isBusy && !files.isRefreshingListing)
                        .allowsHitTesting(!files.isBusy)
                        .contextMenu { if files.features.contains(.mutations) { fileActions(file) } }
                    }
                } header: { Text(files.path.isEmpty ? "Shared folder" : files.path).textCase(nil) }
                Section {
                    Button("Upload file to Mac", systemImage: "square.and.arrow.up") { showImporter = true }.disabled(files.isBusy || !files.canUploadHere)
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Up to 512 MB per file.")
                        if let updateNotice { Text(updateNotice) }
                    }
                }
            }
            .nativeWorkspaceStyle()
            .frame(maxWidth: 840).frame(maxWidth: .infinity)
            .background(Color.workspaceBackground)
            .navigationTitle("Files")
            .searchable(text: $search, prompt: "Search this folder")
            .onChange(of: files.entries, initial: true) { _, _ in updateListing() }
            .onChange(of: search) { _, _ in updateListing() }
            .onChange(of: sortOrder) { _, _ in updateListing() }
            .onChange(of: files.path) { _, _ in search = "" }
            .toolbar {
                if !embedded { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Upload", systemImage: "square.and.arrow.up") { showImporter = true }.disabled(!files.canUploadHere)
                        if files.features.contains(.mutations) {
                            Button("New folder", systemImage: "folder.badge.plus") { renameTarget = nil; newName = ""; editingName = true }
                        }
                    } label: { Image(systemName: "plus") }.accessibilityLabel("Add file or folder")
                        .disabled(files.isBusy || (!files.canUploadHere && !files.features.contains(.mutations)))
                }
                ToolbarItem(placement: .topBarLeading) {
                    RefreshButton(isRefreshing: files.isLoading, isDisabled: files.isBusy && !files.isLoading) {
                        files.list(files.path)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort by", selection: $sortOrder) {
                            ForEach(FileSortOrder.allCases) { order in Text(order.rawValue).tag(order) }
                        }
                    } label: { Image(systemName: "arrow.up.arrow.down") }
                        .accessibilityLabel("Sort files").accessibilityValue(sortOrder.rawValue)
                }
            }
            .onAppear { files.list(files.path) }
            .confirmationDialog("Disconnect from Mac?", isPresented: $showDisconnectConfirmation, titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) { files.onReconnect?() }
            } message: {
                Text("This ends your current connection, including desktop access. Connect again to continue.")
            }
            .alert(renameTarget == nil ? "New folder" : "Rename", isPresented: $editingName) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    if let target = renameTarget { files.mutate(.rename(path: target.path, name: newName)) }
                    else { files.mutate(.createFolder(parent: files.path, name: newName)) }
                }.disabled(newName.isEmpty || newName.contains("/") || newName.utf8.count > 255)
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item]) { result in
                switch result {
                case let .success(url): files.upload(url)
                case let .failure(error): files.error = error.localizedDescription
                }
            }
            .alert("File transfer", isPresented: Binding(get: { files.error != nil && !files.requiresReconnect }, set: { if !$0 && !files.requiresReconnect { files.error = nil } })) {
                Button("OK") { files.error = nil }
            } message: { Text(files.error ?? "") }
        }
    }
    @ViewBuilder private func fileActions(_ file: RemoteFile) -> some View {
        Button("Rename", systemImage: "pencil") { renameTarget = file; newName = file.name; editingName = true }
        Button("Move to Trash", systemImage: "trash", role: .destructive) { trashTarget = file }
    }
}

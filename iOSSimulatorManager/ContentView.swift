import SwiftUI

struct ContentView: View {
    @State private var manager = SimulatorManager()
    @State private var pendingDelete: SimulatorDevice?

    var body: some View {
        NavigationStack {
            Group {
                if manager.isLoading && manager.groups.isEmpty {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !manager.isLoading && manager.groups.isEmpty {
                    ContentUnavailableView(
                        "找不到 iOS 模擬器",
                        systemImage: "iphone.slash",
                        description: Text("沒有已安裝的 iOS 模擬器")
                    )
                } else {
                    simulatorList
                }
            }
            .navigationTitle("iOS Simulator Manager")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if manager.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button {
                            Task { await manager.loadDevices() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("Reload")
                    }
                }
            }
        }
        .frame(minWidth: 620, minHeight: 400)
        .alert("發生錯誤", isPresented: Binding(
            get: { manager.errorMessage != nil },
            set: { if !$0 { manager.errorMessage = nil } }
        )) {
            Button("確定") { manager.errorMessage = nil }
        } message: {
            Text(manager.errorMessage ?? "")
        }
        .confirmationDialog(
            "刪除模擬器",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { device in
            Button("刪除「\(device.name)」", role: .destructive) {
                let udid = device.udid
                pendingDelete = nil
                Task { await manager.deleteDevice(udid: udid) }
            }
            Button("取消", role: .cancel) {
                pendingDelete = nil
            }
        } message: { device in
            Text("確定要刪除模擬器「\(device.name)」嗎？此操作無法復原。")
        }
        .task {
            await manager.loadDevices()
        }
    }

    private var simulatorList: some View {
        List {
            ForEach(manager.groups) { group in
                Section(group.displayName) {
                    ForEach(group.devices) { device in
                        DeviceRow(device: device) {
                            pendingDelete = device
                        }
                    }
                }
            }
        }
    }
}

// MARK: - DeviceRow

struct DeviceRow: View {
    let device: SimulatorDevice
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(device.isBooted ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.body)
                Text(device.udid)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            Text(device.isBooted ? "運行中" : "已關機")
                .font(.caption)
                .foregroundStyle(device.isBooted ? Color.green : Color.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(device.isBooted ? Color.green.opacity(0.15) : Color.secondary.opacity(0.1))
                )

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("刪除模擬器")
        }
        .padding(.vertical, 4)
    }
}

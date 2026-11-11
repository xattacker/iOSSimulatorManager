import Foundation
import Observation

// MARK: - Models

struct SimulatorDevice: Identifiable, Decodable, Sendable {
    let udid: String
    let name: String
    let state: String
    let isAvailable: Bool

    var id: String { udid }
    var isBooted: Bool { state == "Booted" }
}

struct SimulatorGroup: Identifiable {
    let runtime: String
    var devices: [SimulatorDevice]

    var id: String { runtime }

    var displayName: String {
        let bare = runtime.replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
        let parts = bare.components(separatedBy: "-")
        guard parts.count >= 2 else { return bare }
        return "\(parts[0]) \(parts.dropFirst().joined(separator: "."))"
    }
}

// MARK: - Manager

@Observable
@MainActor
final class SimulatorManager {
    var groups: [SimulatorGroup] = []
    var isLoading = false
    var errorMessage: String?

    func loadDevices() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let output = try await shellOutput("/usr/bin/xcrun", args: ["simctl", "list", "devices", "--json"])
            groups = try parseDevices(from: output)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteDevice(udid: String) async {
        isLoading = true
        do {
            try await shellRun("/usr/bin/xcrun", args: ["simctl", "delete", udid])
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            return
        }
        await loadDevices()
    }

    private func parseDevices(from jsonString: String) throws -> [SimulatorGroup] {
        guard let data = jsonString.data(using: .utf8) else {
            throw SimulatorError.invalidOutput
        }

        let response = try JSONDecoder().decode(SimulatorListResponse.self, from: data)

        return response.devices
            .filter { $0.key.contains("iOS") }
            .compactMap { runtime, devices -> SimulatorGroup? in
                let available = devices.filter(\.isAvailable)
                guard !available.isEmpty else { return nil }
                return SimulatorGroup(
                    runtime: runtime,
                    devices: available.sorted { $0.name < $1.name }
                )
            }
            .sorted { $0.runtime > $1.runtime }
    }
}

// MARK: - Private Types

private struct SimulatorListResponse: Decodable {
    let devices: [String: [SimulatorDevice]]
}

enum SimulatorError: LocalizedError {
    case invalidOutput
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidOutput:
            return "無法解析模擬器資料"
        case .commandFailed(let message):
            return message
        }
    }
}

// MARK: - Shell Helpers

private func shellOutput(_ command: String, args: [String]) async throws -> String {
    try await Task.detached(priority: .userInitiated) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw SimulatorError.commandFailed(msg.isEmpty ? "指令執行失敗（exit \(process.terminationStatus)）" : msg)
        }

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }.value
}

private func shellRun(_ command: String, args: [String]) async throws {
    _ = try await shellOutput(command, args: args)
}

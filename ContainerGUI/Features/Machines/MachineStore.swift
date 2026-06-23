import Foundation
import Observation

@MainActor @Observable
final class MachineStore {
    var items: [MachineInfo] = []
    var isLoading = false
    var error: CLIError?

    private let cli = ContainerCLI.shared

    func refresh() async {
        if items.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            items = try await cli.json(["machine", "ls"], as: [MachineInfo].self)
            error = nil
        } catch let cliError as CLIError {
            error = cliError
        } catch {
            self.error = .command(exitCode: -1, stderr: error.localizedDescription)
        }
    }

    func create(
        image: String,
        name: String,
        cpus: String = "",
        memory: String = "",
        homeMount: String = "",
        setDefault: Bool = false,
        noBoot: Bool = false
    ) async throws {
        var args = ["machine", "create", image]
        if !name.isEmpty { args.append(contentsOf: ["--name", name]) }
        if !cpus.isEmpty { args.append(contentsOf: ["--cpus", cpus]) }
        if !memory.isEmpty { args.append(contentsOf: ["--memory", memory]) }
        if !homeMount.isEmpty { args.append(contentsOf: ["--home-mount", homeMount]) }
        if setDefault { args.append("--set-default") }
        if noBoot { args.append("--no-boot") }
        // Pulling the image + first boot can take a while; allow generous time.
        try await cli.run(args, timeout: .seconds(600))
        await refresh()
    }

    /// Applies configuration values (`cpus`, `memory`, `home-mount`). Changes
    /// take effect after the machine is stopped and started again.
    func set(_ machine: MachineInfo, settings: [String: String]) async throws {
        guard !settings.isEmpty else { return }
        var args = ["machine", "set", "--name", machine.name]
        for (key, value) in settings where !value.isEmpty {
            args.append("\(key)=\(value)")
        }
        try await cli.run(args)
        await refresh()
    }

    /// Boots a stopped machine without entering it (`machine run … -- true`).
    /// The machine is persistent, so it stays running afterwards.
    func boot(_ machine: MachineInfo) async throws {
        try await cli.run(["machine", "run", "--name", machine.name, "--", "true"], timeout: .seconds(120))
        await refresh()
    }

    func stop(_ machine: MachineInfo) async throws {
        try await cli.run(["machine", "stop", machine.name])
        await refresh()
    }

    func delete(_ machine: MachineInfo) async throws {
        try await cli.run(["machine", "delete", machine.name])
        await refresh()
    }

    func setDefault(_ machine: MachineInfo) async throws {
        try await cli.run(["machine", "set-default", machine.name])
        await refresh()
    }

    func inspect(_ name: String) async throws -> String {
        try await cli.run(["machine", "inspect", name])
    }
}

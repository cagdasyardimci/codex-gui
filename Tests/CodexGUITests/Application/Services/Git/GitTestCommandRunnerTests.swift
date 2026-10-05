import Darwin
import Foundation
import Testing

struct GitTestCommandRunnerTests
{
	@Test func fixtureFailuresCanRetainStandardErrorDiagnostics() throws
	{
		let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(
			at: root,
			withIntermediateDirectories: true
		)
		defer
		{
			try? FileManager.default.removeItem(at: root)
		}
		let captured = try GitTestCommandRunner.run(
			in: root,
			arguments: ["rev-parse", "--show-toplevel"],
			captureStandardError: true
		)
		#expect(captured.terminationStatus != 0)
		#expect(!captured.output.isEmpty)
		let discarded = try GitTestCommandRunner.run(
			in: root,
			arguments: ["rev-parse", "--show-toplevel"]
		)
		#expect(discarded.terminationStatus == captured.terminationStatus)
		#expect(discarded.output.isEmpty)
	}

	@Test func inheritedGitSettingsCannotRedirectFixtureCommands() throws
	{
		let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(
			at: root,
			withIntermediateDirectories: true
		)
		defer
		{
			try? FileManager.default.removeItem(at: root)
		}
		let globalConfig = root.appendingPathComponent("global-config")
		try Data("[user]\n\tname = Host User\n".utf8).write(to: globalConfig)
		var inheritedEnvironment = ProcessInfo.processInfo.environment
		inheritedEnvironment["GIT_DIR"] = root.appendingPathComponent("wrong-git-dir").path
		inheritedEnvironment["GIT_CONFIG_GLOBAL"] = globalConfig.path
		inheritedEnvironment["GIT_CONFIG_COUNT"] = "1"
		inheritedEnvironment["GIT_CONFIG_KEY_0"] = "core.fsmonitor"
		inheritedEnvironment["GIT_CONFIG_VALUE_0"] = "touch monitor-ran"

		let initialized = try GitTestCommandRunner.run(
			in: root,
			arguments: ["init", "-q"],
			environment: inheritedEnvironment
		)
		#expect(initialized.terminationStatus == 0)
		let topLevel = try GitTestCommandRunner.run(
			in: root,
			arguments: ["rev-parse", "--show-toplevel"],
			environment: inheritedEnvironment
		)
		#expect(topLevel.terminationStatus == 0)
		let canonicalRoot = try #require(realpath(
			root.path,
			nil
		))
		defer
		{
			free(canonicalRoot)
		}
		#expect(String(
			decoding: topLevel.output,
			as: UTF8.self
		)
		.trimmingCharacters(in: .whitespacesAndNewlines) == String(cString: canonicalRoot))
		let fsmonitor = try GitTestCommandRunner.run(
			in: root,
			arguments: ["config", "--get", "core.fsmonitor"],
			environment: inheritedEnvironment
		)
		#expect(fsmonitor.terminationStatus == 0)
		#expect(fsmonitor.output == Data("false\n".utf8))
		let userName = try GitTestCommandRunner.run(
			in: root,
			arguments: ["config", "--get", "user.name"],
			environment: inheritedEnvironment
		)
		#expect(userName.terminationStatus == 1)
	}
}

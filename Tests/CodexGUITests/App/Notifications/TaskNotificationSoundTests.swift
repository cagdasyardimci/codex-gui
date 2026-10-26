import Foundation
import Testing

@testable import CodexGUI

@Suite
struct TaskNotificationSoundTests
{
	@Test(arguments: [true, false])
	func legacySoundMigratesOnceAndPreservesAlertFilters(enabled: Bool) throws
	{
		let domain = "TaskNotificationSoundTests-\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: domain))
		defer
		{
			defaults.removePersistentDomain(forName: domain)
		}
		defaults.set(
			enabled,
			forKey: "taskNotificationSoundEnabled"
		)
		defaults.set(
			"whenUnfocused",
			forKey: "taskNotificationCompletionMode"
		)
		defaults.set(
			false,
			forKey: "taskNotificationPermissionAlerts"
		)
		defaults.set(
			true,
			forKey: "taskNotificationQuestionAlerts"
		)
		let preferences = TaskNotificationPreferences(defaults: defaults)
		#expect(preferences.sound == (enabled ? .default : .none))
		defaults.set(
			!enabled,
			forKey: "taskNotificationSoundEnabled"
		)
		#expect(TaskNotificationPreferences(defaults: defaults).sound == preferences.sound)
		#expect(!preferences.allows(
			.completion,
			appIsActive: true
		))
		#expect(preferences.allows(
			.completion,
			appIsActive: false
		))
		#expect(!preferences.permissionAlerts)
		#expect(preferences.questionAlerts)
	}

	@Test func selectedSoundAndCustomFilenameRoundTripInAnIsolatedDomain() throws
	{
		let domain = "TaskNotificationSoundTests-\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: domain))
		defer
		{
			defaults.removePersistentDomain(forName: domain)
		}
		let preferences = TaskNotificationPreferences(defaults: defaults)
		#expect(preferences.sound == .default)
		preferences.sound = .custom
		preferences.customSoundFilename = "CodexGUI-owned.wav"
		let restored = TaskNotificationPreferences(defaults: defaults)
		#expect(restored.sound == .custom)
		#expect(restored.customSoundFilename == "CodexGUI-owned.wav")
		preferences.soundEnabled = false
		#expect(restored.sound == .none)
		#expect(restored.customSoundFilename == "CodexGUI-owned.wav")
		preferences.customSoundFilename = "../unowned.wav"
		#expect(restored.customSoundFilename == nil)
	}

	@Test func customImportPublishesExactValidatedBytesAndResolvesOnlyOwnedFiles() async throws
	{
		let fixture = try await SoundFileFixture.make()
		defer
		{
			fixture.close()
		}
		let source = try await fixture.wav(duration: 0.1)
		let filename = try #require(try await fixture.library.prepare(
			.custom,
			customFile: source
		))
		#expect(filename.hasPrefix("CodexGUI-"))
		let installed = try #require(fixture.library.fileURL(
			for: .custom,
			customFilename: filename
		))
		#expect(installed.deletingLastPathComponent() == fixture.library.directory)
		#expect(try Data(contentsOf: source) == Data(contentsOf: installed))
		let unowned = fixture.library.directory.appendingPathComponent("OtherApp.wav")
		try FileManager.default.copyItem(
			at: installed,
			to: unowned
		)
		#expect(fixture.library.fileURL(
			for: .custom,
			customFilename: unowned.lastPathComponent
		) == nil)
		#expect(fixture.library.notificationSound(
			for: .custom,
			customFilename: filename
		) != nil)
		#expect(fixture.library.notificationSound(
			for: .none,
			customFilename: filename
		) == nil)
		#expect(fixture.library.fileURL(
			for: .custom,
			customFilename: "../outside.wav"
		) == nil)
		#expect(fixture.library
			.fileURL(
				for: .custom,
				customFilename: "CodexGUI-missing.wav"
			) == nil)
	}

	@Test(arguments: ["long", "corrupt", "unsupported"])
	func invalidImportsDoNotPublishAUsableSound(kind: String) async throws
	{
		let fixture = try await SoundFileFixture.make()
		defer
		{
			fixture.close()
		}
		let source: URL
		if kind == "long"
		{
			source = try await fixture.wav(duration: 30)
		}
		else
		{
			source = fixture.directory
				.appendingPathComponent(kind == "corrupt" ? "bad.wav" : "bad.mp3")
			try Data("not audio".utf8).write(to: source)
		}
		await #expect(throws: (any Error).self)
		{
			_ = try await fixture.library.prepare(
				.custom,
				customFile: source
			)
		}
		let installed = (try? FileManager.default.contentsOfDirectory(
			at: fixture.library.directory,
			includingPropertiesForKeys: nil
		)) ?? []
		#expect(installed.isEmpty)
	}

	@Test func classicInstallsSosumiUnderAnOwnedNotificationFilename() async throws
	{
		let fixture = try await SoundFileFixture.make()
		defer
		{
			fixture.close()
		}
		let filename = try await fixture.library.prepare(.classic)
		#expect(filename == "CodexGUI-Classic.aiff")
		let installed = try #require(fixture.library.fileURL(
			for: .classic,
			customFilename: nil
		))
		#expect(try Data(contentsOf: installed) == Data(contentsOf:
			URL(fileURLWithPath: "/System/Library/Sounds/Sosumi.aiff")))
	}
}

private struct SoundFileFixture: Sendable
{
	let directory: URL
	var library: TaskNotificationSoundLibrary
	{
		TaskNotificationSoundLibrary(directory: directory.appendingPathComponent("Sounds"))
	}

	static func make() async throws -> SoundFileFixture
	{
		try await BackgroundTestWork.perform
		{
			let directory = FileManager.default.temporaryDirectory
				.appendingPathComponent("TaskNotificationSoundTests-\(UUID().uuidString)")
			try FileManager.default.createDirectory(
				at: directory,
				withIntermediateDirectories: true
			)
			return SoundFileFixture(directory: directory)
		}
	}

	func close()
	{
		try? FileManager.default.removeItem(at: directory)
	}

	func wav(duration: Double) async throws -> URL
	{
		try await BackgroundTestWork.perform
		{
			let sampleRate: UInt32 = 8000
			let payloadSize = UInt32(duration * Double(sampleRate)) * 2
			var data = Data("RIFF".utf8)
			Self.append(
				payloadSize + 36,
				to: &data
			)
			data.append(Data("WAVEfmt ".utf8))
			Self.append(
				UInt32(16),
				to: &data
			)
			Self.append(
				UInt16(1),
				to: &data
			)
			Self.append(
				UInt16(1),
				to: &data
			)
			Self.append(
				sampleRate,
				to: &data
			)
			Self.append(
				sampleRate * 2,
				to: &data
			)
			Self.append(
				UInt16(2),
				to: &data
			)
			Self.append(
				UInt16(16),
				to: &data
			)
			data.append(Data("data".utf8))
			Self.append(
				payloadSize,
				to: &data
			)
			data.append(Data(count: Int(payloadSize)))
			let url = directory.appendingPathComponent("sample-\(UUID().uuidString).wav")
			try data.write(to: url)
			return url
		}
	}

	private static func append<Value: FixedWidthInteger>(
		_ value: Value,
		to data: inout Data
	)
	{
		var littleEndian = value.littleEndian
		withUnsafeBytes(of: &littleEndian)
		{
			data.append(contentsOf: $0)
		}
	}
}

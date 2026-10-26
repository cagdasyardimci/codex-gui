import AVFoundation
import Foundation
import UserNotifications

enum TaskNotificationSound: String, CaseIterable, Sendable
{
	case `default`, classic, none, basso, glass, ping, pop, purr, tink, custom

	var title: String
	{
		switch self
		{
		case .default: "Default"
		case .classic: "Classic"
		case .none: "None"
		case .custom: "Custom…"
		default: rawValue.capitalized
		}
	}

	var systemFilename: String?
	{
		switch self
		{
		case .classic: "Sosumi.aiff"
		case .basso, .glass, .ping, .pop, .purr, .tink: title + ".aiff"
		case .default, .none, .custom: nil
		}
	}
}

/// Installs validated audio where UserNotifications can resolve a named notification sound.
struct TaskNotificationSoundLibrary: Sendable
{
	let directory: URL
	let systemDirectory: URL

	init(
		directory: URL = FileManager.default.urls(
			for: .libraryDirectory,
			in: .userDomainMask
		)[0]
			.appendingPathComponent(
				"Sounds",
				isDirectory: true
			),
		systemDirectory: URL = URL(
			fileURLWithPath: "/System/Library/Sounds",
			isDirectory: true
		)
	)
	{
		self.directory = directory
		self.systemDirectory = systemDirectory
	}

	func prepare(
		_ selection: TaskNotificationSound,
		customFile: URL? = nil
	) async throws -> String?
	{
		let work = Task.detached(priority: .utility)
		{
			try prepareSynchronously(
				selection,
				customFile: customFile
			)
		}
		return try await withTaskCancellationHandler
		{
			try await work.value
		}
		onCancel:
		{
			work.cancel()
		}
	}

	func fileURL(
		for selection: TaskNotificationSound,
		customFilename: String?
	) -> URL?
	{
		let filename: String
		switch selection
		{
		case .default, .none: return nil
		case .custom:
			guard let customFilename, Self.isSafeFilename(customFilename)
			else
			{
				return nil
			}
			filename = customFilename
		default: filename = "CodexGUI-" + selection.title + ".aiff"
		}
		let url = directory.appendingPathComponent(filename)
		return FileManager.default.fileExists(atPath: url.path) ? url : nil
	}

	func notificationSound(
		for selection: TaskNotificationSound,
		customFilename: String?
	) -> UNNotificationSound?
	{
		if selection == .default
		{
			return .default
		}
		guard selection != .none,
				let url = fileURL(
				for: selection,
				customFilename: customFilename
				)
		else
		{
			return nil
		}
		return UNNotificationSound(named: UNNotificationSoundName(url.lastPathComponent))
	}

	static func isSafeFilename(_ filename: String) -> Bool
	{
		filename.hasPrefix("CodexGUI-")
			&& (filename as NSString).lastPathComponent == filename
			&& !filename.contains("\\")
			&& ["wav", "aiff", "aif", "caf"].contains(
				(filename as NSString).pathExtension.lowercased()
			)
	}

	private func prepareSynchronously(
		_ selection: TaskNotificationSound,
		customFile: URL?
	) throws -> String?
	{
		try Task.checkCancellation()
		if selection == .default || selection == .none
		{
			return nil
		}
		let source: URL
		let filename: String
		if selection == .custom
		{
			guard let customFile
			else
			{
				throw SoundError.missingFile
			}
			source = customFile
			let ext = source.pathExtension.lowercased()
			guard ["wav", "aiff", "aif", "caf"].contains(ext)
			else
			{
				throw SoundError.unsupportedType
			}
			filename = "CodexGUI-\(UUID().uuidString).\(ext)"
		}
		else
		{
			guard let systemFilename = selection.systemFilename
			else
			{
				return nil
			}
			source = systemDirectory.appendingPathComponent(systemFilename)
			filename = "CodexGUI-" + selection.title + ".aiff"
		}
		let resources = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
		guard resources.isRegularFile == true, let size = resources.fileSize,
				size > 0, size <= 32 * 1024 * 1024
		else
		{
			throw SoundError.invalidFile
		}
		let data = try Data(contentsOf: source)
		guard data.count <= 32 * 1024 * 1024
		else
		{
			throw SoundError.invalidFile
		}
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)
		let temporary = directory.appendingPathComponent(".CodexGUI-\(UUID().uuidString).tmp")
		defer
		{
			try? FileManager.default.removeItem(at: temporary)
		}
		try data.write(
			to: temporary,
			options: .atomic
		)
		try validate(temporary)
		try Task.checkCancellation()
		try data.write(
			to: directory.appendingPathComponent(filename),
			options: .atomic
		)
		return filename
	}

	private func validate(_ url: URL) throws
	{
		let audio = try AVAudioFile(forReading: url)
		let format = audio.fileFormat.streamDescription.pointee.mFormatID
		guard [kAudioFormatLinearPCM, kAudioFormatAppleIMA4, kAudioFormatULaw, kAudioFormatALaw]
			.contains(format)
		else
		{
			throw SoundError.unsupportedType
		}
		let duration = Double(audio.length) / audio.processingFormat.sampleRate
		guard duration.isFinite, duration > 0, duration < 30
		else
		{
			throw SoundError.duration
		}
		guard let buffer = AVAudioPCMBuffer(
			pcmFormat: audio.processingFormat,
			frameCapacity: 4096
		)
		else
		{
			throw SoundError.invalidFile
		}
		while audio.framePosition < audio.length
		{
			try Task.checkCancellation()
			try audio.read(into: buffer)
			guard buffer.frameLength > 0
			else
			{
				throw SoundError.invalidFile
			}
		}
	}

	enum SoundError: LocalizedError
	{
		case missingFile, unsupportedType, invalidFile, duration

		var errorDescription: String?
		{
			switch self
			{
			case .missingFile: "Choose a sound file."
			case .unsupportedType: "Choose a WAV, AIFF, or CAF file with supported alert audio."
			case .invalidFile: "Choose a valid audio file smaller than 32 MB."
			case .duration: "Notification sounds must be shorter than 30 seconds."
			}
		}
	}
}

import Foundation

struct Configuration
{
	var action = "test"
	var root = URL(fileURLWithPath: #filePath)
		.deletingLastPathComponent().deletingLastPathComponent()
		.deletingLastPathComponent().deletingLastPathComponent()
	var backend: URL?
	var run: URL?
	var repetitions = 1
	var compact = false
	var scenario = "streaming"
	var timeout: Double = 300
	var developerDirectory = ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
		?? "/Applications/Xcode.app/Contents/Developer"

	init(_ arguments: [String]) throws
	{
		if arguments.isEmpty || arguments == ["--help"] || arguments == ["help"]
		{
			action = "help"
			return
		}
		action = arguments[0]
		guard ["test", "report"].contains(action)
		else
		{
			throw ToolError.invalid("Use test, report or --help")
		}
		var index = 1
		while index < arguments.count
		{
			let option = arguments[index]
			guard index + 1 < arguments.count
			else
			{
				throw ToolError.invalid("Missing value for " + option)
			}
			let value = arguments[index + 1]
			switch option
			{
			case "--root": root = try Self.absolute(value)
			case "--backend": backend = try Self.absolute(value)
			case "--run": run = try Self.absolute(value)
			case "--repeat":
				guard let count = Int(value), (1 ... 100).contains(count)
				else
				{
					throw ToolError.invalid("--repeat must be 1..100")
				}
				repetitions = count
			case "--compact":
				guard ["0", "1"].contains(value)
				else
				{
					throw ToolError.invalid("--compact must be 0 or 1")
				}
				compact = value == "1"
			case "--scenario": scenario = value
			case "--timeout":
				guard let seconds = Double(value), seconds.isFinite, seconds >= 1
				else
				{
					throw ToolError.invalid("--timeout must be positive seconds")
				}
				timeout = seconds
			case "--developer-dir": developerDirectory = try Self.absolute(value).path
			default: throw ToolError.invalid("Unknown option: " + option)
			}
			index += 2
		}
		guard FileManager.default.fileExists(
			atPath: root.appendingPathComponent("Tests/E2E/Package.swift").path
		)
		else
		{
			throw ToolError.invalid("--root must identify this repository")
		}
		if action == "report", run == nil
		{
			throw ToolError.invalid("report requires --run")
		}
		if let backend, !FileManager.default.isExecutableFile(atPath: backend.path)
		{
			throw ToolError.invalid("--backend must name an executable file")
		}
	}

	static func absolute(_ value: String) throws -> URL
	{
		guard value.hasPrefix("/")
		else
		{
			throw ToolError.invalid("Path must be absolute: " + value)
		}
		return URL(fileURLWithPath: value).standardizedFileURL
	}

	static let help = """
    E2EWorkflow test [--repeat 1..100] [--compact 0|1]
                     [--backend /path] [--scenario NAME] [--timeout SECONDS]
    E2EWorkflow report --run /absolute/path/to/run
    Both commands accept --root /repository and --developer-dir /Xcode/Contents/Developer.
    """
}

import Foundation
import Darwin

do
{
	let configuration = try Configuration(Array(CommandLine.arguments.dropFirst()))
	if configuration.action == "help"
	{
		output(Configuration.help)
		exit(0)
	}
	guard FileManager.default.changeCurrentDirectoryPath(configuration.root.path)
	else
	{
		throw ToolError.invalid("Cannot enter repository")
	}
	setenv(
		"DEVELOPER_DIR",
		configuration.developerDirectory,
		1
	)
	signal(
		SIGINT,
		handleSignal
	)
	signal(
		SIGTERM,
		handleSignal
	)
	let status = try configuration.action == "report"
		? reassess(configuration) : runWorkflow(configuration)
	exit(interrupted == 0 ? status : 130)
}
catch
{
	FileHandle.standardError.write(Data((String(describing: error) + "\n").utf8))
	exit(interrupted == 0 ? 1 : 130)
}

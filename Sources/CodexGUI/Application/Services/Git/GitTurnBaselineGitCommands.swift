import Foundation

/// Baseline capture uses only manifests, so no clean-filter conversion is requested.
/// The comparison runs outside any repository with explicit --no-index and no external diff.
struct GitTurnBaselineGitCommands
{
	let root: String
	let maximumBytes: Int

	func run(
		_ arguments: [String],
		acceptsDifference: Bool = false
	) throws -> Data
	{
		let gitArguments = [
			"--no-optional-locks",
			"-c",
			"core.fsmonitor=false",
			"-c",
			"core.quotePath=true",
			"-C",
			root
		] + arguments
		let output: GitCommandOutput
		do
		{
			output = try GitCommandRunner.run(
				arguments: gitArguments,
				maximumBytes: maximumBytes
			)
		}
		catch GitCommandRunnerError.oversized
		{
			throw GitTurnBaselineReadError.failure(.oversized)
		}
		let isSuccessful = output.terminationStatus == 0
		let isAcceptedDifference = acceptsDifference && output.terminationStatus == 1
		guard isSuccessful || isAcceptedDifference
		else
		{
			throw GitTurnBaselineReadError
				.failure(.lastTurnBaselineUnavailable("Git could not read the tracked comparison."))
		}
		return output.bytes
	}
}

import Darwin
import Foundation

extension GitWorktreeManager
{
	func verifyOwnership(of workspace: TaskWorkspace) throws
	{
		try validateManagedIdentity(of: workspace)
		let checkout = URL(fileURLWithPath: workspace.checkoutPath)
		let source = sourceURL(for: workspace)
		try verifyCheckoutRegistration(
			checkout,
			at: source
		)
		try verifyCheckoutGitIdentity(
			workspace,
			at: checkout
		)
	}

	private func verifyCheckoutRegistration(
		_ checkout: URL,
		at source: URL
	) throws
	{
		guard pathExists(checkout.path)
		else
		{
			throw TaskWorkspaceError.ownershipConflict("checkout path is missing: \(checkout.path)")
		}
		guard canonicalURL(for: checkout).path == checkout.path
		else
		{
			throw TaskWorkspaceError
				.ownershipConflict("checkout path was replaced: \(checkout.path)")
		}
		guard try isRegistered(
			checkout.path,
			at: source
		)
		else
		{
			throw TaskWorkspaceError.ownershipConflict("Git does not register \(checkout.path)")
		}
	}

	private func verifyCheckoutGitIdentity(
		_ workspace: TaskWorkspace,
		at checkout: URL
	) throws
	{
		let top = try? gitOutput(
			["rev-parse", "--show-toplevel"],
			at: checkout
		)
		guard top.map(
			{
				canonicalURL(for: URL(fileURLWithPath: $0)).path
			}
		) == checkout.path
		else
		{
			throw TaskWorkspaceError.ownershipConflict(
				"Git reports another checkout root: \(top ?? "missing")"
			)
		}
		let common = try? gitOutput(
			["rev-parse", "--path-format=absolute", "--git-common-dir"],
			at: checkout
		)
		guard
			common.map(
				{
					canonicalURL(for: URL(fileURLWithPath: $0)).path
				}
			)
			== workspace.repositoryGitDirectory
		else
		{
			throw TaskWorkspaceError.ownershipConflict(
				"Git reports another repository: \(common ?? "missing")"
			)
		}
		let branch = try? gitOutput(
			["symbolic-ref", "--quiet", "--short", "HEAD"],
			at: checkout
		)
		guard branch == workspace.branch
		else
		{
			throw TaskWorkspaceError.ownershipConflict(
				"Git reports another branch: \(branch ?? "missing")"
			)
		}
	}

	func validateManagedIdentity(of workspace: TaskWorkspace) throws
	{
		let suffix = "-\(workspace.id.uuidString.lowercased())"
		let prefix = "codex/task/"
		let checkout = URL(fileURLWithPath: workspace.checkoutPath)
		let managedRoot = canonicalURL(for: checkoutRoot).path
		guard workspace.branch.hasPrefix(prefix), workspace.branch.hasSuffix(suffix),
				String(workspace.branch.dropFirst(prefix.count)) == checkout.lastPathComponent,
				canonicalURL(for: checkout.deletingLastPathComponent()).path == managedRoot
		else
		{
			throw TaskWorkspaceError
				.ownershipConflict("record names or checkout directory were changed")
		}
		let source = sourceURL(for: workspace)
		let common = try? gitOutput(
			["rev-parse", "--path-format=absolute", "--git-common-dir"],
			at: source
		)
		guard
			common.map(
				{
					canonicalURL(for: URL(fileURLWithPath: $0)).path
				}
			)
			== workspace.repositoryGitDirectory
		else
		{
			throw TaskWorkspaceError
				.ownershipConflict("source repository no longer matches its record")
		}
	}

	func isDirty(
		_ path: String,
		includeIgnored: Bool
	) throws -> Bool
	{
		var arguments = ["status", "--porcelain=v1", "--untracked-files=all"]
		if includeIgnored
		{
			arguments.append("--ignored=matching")
		}
		return try !gitOutput(
			arguments,
			at: URL(fileURLWithPath: path)
		).isEmpty
	}

	func branchExists(
		_ branch: String,
		at source: URL
	) throws -> Bool
	{
		let result = try runGit(
			["show-ref", "--verify", "--quiet", "refs/heads/\(branch)"],
			at: source
		)
		if result.status == 0
		{
			return true
		}
		if result.status == 1
		{
			return false
		}
		throw TaskWorkspaceError.gitFailure(result.output)
	}

	func isRegistered(
		_ path: String,
		at source: URL
	) throws -> Bool
	{
		try worktreePaths(at: source).contains(path)
	}

	func isBranchCheckedOut(
		_ branch: String,
		at source: URL
	) throws -> Bool
	{
		try worktreeFields(at: source).contains("branch refs/heads/\(branch)")
	}

	func worktreePaths(at source: URL) throws -> [String]
	{
		try worktreeFields(at: source).compactMap
		{
			field in
			guard field.hasPrefix("worktree ")
			else
			{
				return nil
			}
			let listed = String(field.dropFirst("worktree ".count))
			return canonicalURL(for: URL(fileURLWithPath: listed)).path
		}
	}

	private func worktreeFields(at source: URL) throws -> [String]
	{
		try gitOutput(
			["worktree", "list", "--porcelain", "-z"],
			at: source
		).split(separator: "\0").map(String.init)
	}

	func gitOutput(
		_ arguments: [String],
		at directory: URL
	) throws -> String
	{
		let result = try runGit(
			arguments,
			at: directory
		)
		guard result.status == 0
		else
		{
			throw TaskWorkspaceError.gitFailure(
				"git \(arguments.joined(separator: " ")): \(result.output)"
			)
		}
		return result.output.trimmingCharacters(in: .newlines)
	}

	private func runGit(
		_ arguments: [String],
		at directory: URL
	) throws -> GitResult
	{
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
		process.currentDirectoryURL = directory
		process.arguments = arguments

		let output = Pipe()
		process.standardOutput = output
		process.standardError = output

		do
		{
			try process.run()
		}
		catch
		{
			throw TaskWorkspaceError.gitFailure(error.localizedDescription)
		}

		output.fileHandleForWriting.closeFile()
		let data = output.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		return GitResult(
			status: process.terminationStatus,
			output: String(
				decoding: data,
				as: UTF8.self
			)
		)
	}

	func sourceURL(for workspace: TaskWorkspace) -> URL
	{
		URL(fileURLWithPath: workspace.sourceProjectPath)
	}

	func canonicalURL(for url: URL) -> URL
	{
		url.standardizedFileURL.resolvingSymlinksInPath()
	}

	private func isInside(
		_ path: String,
		parent: String
	) -> Bool
	{
		path == parent || path.hasPrefix(parent + "/")
	}

	func isSafeCheckoutRoot(
		_ path: String,
		worktreePaths: [String],
		gitDirectory: String
	) -> Bool
	{
		!worktreePaths.contains(where:
			{
				isInside(
					path,
					parent: $0
				)
			})
			&& !isInside(
				path,
				parent: gitDirectory
			)
	}

	func pathExists(_ path: String) -> Bool
	{
		var value = stat()
		return path.withCString
		{
			Darwin.lstat(
				$0,
				&value
			) == 0
		}
	}

	static func slug(from name: String) -> String
	{
		let words = name.lowercased().split
		{
			!$0.isASCII || !$0.isLetter && !$0.isNumber
		}
		let value = words.joined(separator: "-")
		let trimmed = String(value.prefix(32))
			.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
		return trimmed.isEmpty ? "task" : trimmed
	}
}

private struct GitResult
{
	let status: Int32
	let output: String
}

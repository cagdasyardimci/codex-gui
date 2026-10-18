import Foundation

enum FileGitHubURL
{
	static func make(
		origin: String,
		commit: String,
		relativePath: String
	) -> URL?
	{
		let trimmed = origin.trimmingCharacters(in: .whitespacesAndNewlines)
		let repositoryPath: String
		if trimmed.hasPrefix("git@github.com:")
		{
			repositoryPath = String(trimmed.dropFirst("git@github.com:".count))
		}
		else if let url = URLComponents(string: trimmed),
				url.host?.lowercased() == "github.com",
				["https", "ssh"].contains(url.scheme?.lowercased() ?? ""),
				url.user == nil || url.user == "git"
		{
			repositoryPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
		}
		else
		{
			return nil
		}
		let path = repositoryPath.hasSuffix(".git")
			? String(repositoryPath.dropLast(4)) : repositoryPath
		let repository = path.split(
			separator: "/",
			omittingEmptySubsequences: false
		)
		guard repository.count == 2,
				repository.allSatisfy(
				{
					!$0.isEmpty && $0 != "." && $0 != ".."
				}
				),
				[40, 64].contains(commit.count),
				commit.allSatisfy(\.isHexDigit),
				!relativePath.isEmpty
		else
		{
			return nil
		}
		let parts = relativePath.split(
			separator: "/",
			omittingEmptySubsequences: false
		)
		guard parts.allSatisfy(
			{
				!$0.isEmpty && $0 != "." && $0 != ".."
			}
		)
		else
		{
			return nil
		}
		var components = URLComponents()
		components.scheme = "https"
		components.host = "github.com"
		let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%"))
		let segments = repository.map(String.init) + ["blob", commit] + parts.map(String.init)
		components.percentEncodedPath = "/" + segments.map
		{
			$0.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
		}.joined(separator: "/")
		return components.url
	}

	static func resolve(location: FileLocation) throws -> URL
	{
		let origin = try git(
			["remote", "get-url", "origin"],
			root: location.root
		)
		let commit = try git(
			["rev-parse", "HEAD"],
			root: location.root
		)
		let repositoryRoot = try git(
			["rev-parse", "--show-toplevel"],
			root: location.root
		)
		let root = URL(fileURLWithPath: repositoryRoot).standardizedFileURL
			.resolvingSymlinksInPath()
		let browsingRoot = URL(fileURLWithPath: location.root).standardizedFileURL
			.resolvingSymlinksInPath()
		let file = browsingRoot.appendingPathComponent(location.relativePath).standardizedFileURL
		let prefix = root.path == "/" ? "/" : root.path + "/"
		guard file.path.utf8.starts(with: prefix.utf8)
		else
		{
			throw error("This file is outside the Git repository.")
		}
		let relativePath = String(
			decoding: file.path.utf8.dropFirst(prefix.utf8.count),
			as: UTF8.self
		)
		guard let url = make(
			origin: origin,
			commit: commit,
			relativePath: relativePath
		)
		else
		{
			throw error("This file has no usable GitHub origin or commit.")
		}
		return url
	}

	private static func git(
		_ command: [String],
		root: String
	) throws -> String
	{
		let output = try GitCommandRunner.run(
			arguments: ["-C", root] + command,
			maximumBytes: 4096
		)
		guard output.terminationStatus == 0,
				let value = String(
				data: output.bytes,
				encoding: .utf8
				)?
				.trimmingCharacters(in: .whitespacesAndNewlines),
				!value.isEmpty
		else
		{
			throw error("GitHub is unavailable for this file.")
		}
		return value
	}

	private static func error(_ message: String) -> NSError
	{
		NSError(
			domain: "FileGitHubURL",
			code: 1,
			userInfo: [NSLocalizedDescriptionKey: message]
		)
	}
}

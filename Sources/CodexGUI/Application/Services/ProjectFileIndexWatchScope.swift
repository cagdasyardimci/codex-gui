import Darwin
import Foundation

/// Tracks the physical checkout and the parent directories that can replace its path aliases.
struct ProjectFileIndexWatchScope: Sendable, Equatable
{
	struct DirectoryIdentity: Sendable, Equatable
	{
		let path: String
		private let pathBytes: Data
		private let device: dev_t
		private let inode: ino_t
		private let creationSeconds: Int
		private let creationNanoseconds: Int

		init?(path: String)
		{
			guard let resolvedPath = realpath(
				path,
				nil
			)
			else
			{
				return nil
			}
			defer
			{
				free(resolvedPath)
			}
			var metadata = stat()
			guard stat(
				resolvedPath,
				&metadata
			) == 0,
				metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
			else
			{
				return nil
			}
			self.path = String(cString: resolvedPath)
			pathBytes = Data(self.path.utf8)
			device = metadata.st_dev
			inode = metadata.st_ino
			creationSeconds = metadata.st_birthtimespec.tv_sec
			creationNanoseconds = metadata.st_birthtimespec.tv_nsec
		}
	}

	let projectPath: String
	let root: DirectoryIdentity?
	let parentDirectories: [DirectoryIdentity]

	var isCurrent: Bool
	{
		Self.capture(projectPath: projectPath) == self
	}

	static func capture(projectPath: String) -> Self?
	{
		let projectURL = URL(fileURLWithPath: projectPath).standardizedFileURL
		var parentDirectories: [DirectoryIdentity] = []
		var inspectedPaths: Set<Data> = []
		collectPathParents(
			for: projectURL,
			into: &parentDirectories,
			inspectedPaths: &inspectedPaths
		)
		let root = DirectoryIdentity(path: projectURL.path)
		if let root
		{
			appendParentDirectory(
				URL(fileURLWithPath: root.path).deletingLastPathComponent(),
				to: &parentDirectories
			)
		}
		guard !parentDirectories.isEmpty
		else
		{
			return nil
		}
		return ProjectFileIndexWatchScope(
			projectPath: projectPath,
			root: root,
			parentDirectories: parentDirectories
		)
	}

	private static func collectPathParents(
		for url: URL,
		into parents: inout [DirectoryIdentity],
		inspectedPaths: inout Set<Data>
	)
	{
		// Bound symbolic-link traversal, including links in a link's destination path.
		let maximumInspectedAliasPaths = 40
		guard inspectedPaths.count < maximumInspectedAliasPaths,
				inspectedPaths.insert(Data(url.path.utf8)).inserted
		else
		{
			return
		}
		var currentURL = URL(
			fileURLWithPath: "/",
			isDirectory: true
		)
		for component in url.pathComponents.dropFirst()
		{
			let parentURL = currentURL
			currentURL.appendPathComponent(component)
			var metadata = stat()
			guard lstat(
				currentURL.path,
				&metadata
			) == 0
			else
			{
				// Keep observing the nearest existing parent while a checkout path is absent.
				appendParentDirectory(
					parentURL,
					to: &parents
				)
				return
			}
			guard metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFLNK)
			else
			{
				continue
			}
			appendParentDirectory(
				parentURL,
				to: &parents
			)
			if let destination = try? FileManager.default.destinationOfSymbolicLink(
				atPath: currentURL.path
			)
			{
				let destinationURL = destination.hasPrefix("/")
					? URL(fileURLWithPath: destination)
					: parentURL.appendingPathComponent(destination)
				collectPathParents(
					for: destinationURL.standardizedFileURL,
					into: &parents,
					inspectedPaths: &inspectedPaths
				)
			}
		}
		appendParentDirectory(
			url.deletingLastPathComponent(),
			to: &parents
		)
	}

	private static func appendParentDirectory(
		_ url: URL,
		to parents: inout [DirectoryIdentity]
	)
	{
		guard let parent = DirectoryIdentity(path: url.path), !parents.contains(parent)
		else
		{
			return
		}
		parents.append(parent)
	}
}

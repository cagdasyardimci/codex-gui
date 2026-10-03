import Darwin
import Foundation

/// Identity stays independent of tree position, refreshes, and the displayed conversation.
struct WorkspaceFileIdentity: Hashable, Sendable
{
	let checkoutRoot: String
	let relativePath: String

	init?(checkoutRoot: URL, relativePath: String)
	{
		guard !relativePath.hasPrefix("/"), !relativePath.contains("\0")
		else
		{
			return nil
		}
		var components: [String] = []
		for component in relativePath.split(separator: "/")
		{
			if component == "."
			{
				continue
			}
			if component == ".."
			{
				guard !components.isEmpty
				else
				{
					return nil
				}
				components.removeLast()
			}
			else
			{
				components.append(String(component))
			}
		}
		guard !components.isEmpty
		else
		{
			return nil
		}
		self.checkoutRoot = Self.canonicalRootPath(checkoutRoot)
		self.relativePath = components.joined(separator: "/")
	}
	/// realpath preserves the physical root, including macOS's /var and /tmp aliases. Missing
	/// suffixes retain the canonical existing ancestor so missing roots remain identifiable.
	static func canonicalRootPath(_ root: URL) -> String
	{
		var ancestor = root.standardizedFileURL
		var missingComponents: [String] = []
		while true
		{
			if let resolved = realpath(
				ancestor.path,
				nil
			)
			{
				defer
				{
					free(resolved)
				}
				var path = String(cString: resolved)
				for component in missingComponents.reversed()
				{
					path = URL(fileURLWithPath: path).appendingPathComponent(component).path
				}
				return path
			}
			guard ancestor.path != "/"
			else
			{
				return root.standardizedFileURL.path
			}
			missingComponents.append(ancestor.lastPathComponent)
			ancestor.deleteLastPathComponent()
		}
	}

	init(
		checkoutRootPath: String,
		normalizedRelativePath: String
	)
	{
		checkoutRoot = checkoutRootPath
		relativePath = normalizedRelativePath
	}
}

struct WorkspaceFileVersion: Equatable, Hashable, Sendable
{
	let device: Int32
	let inode: UInt64
	let byteCount: Int64
	let modifiedSeconds: Int64
	let modifiedNanoseconds: Int64
	let changedSeconds: Int64
	let changedNanoseconds: Int64
}

enum WorkspaceFileKind: Equatable, Sendable
{
	case directory
	case file
	case symbolicLink
	case other
}

struct WorkspaceFileNode: Identifiable, Equatable, Sendable
{
	let id: WorkspaceFileIdentity
	let name: String
	let kind: WorkspaceFileKind
	let version: WorkspaceFileVersion
	let children: [WorkspaceFileNode]
}

struct WorkspaceFileTreeIssue: Equatable, Sendable
{
	let relativePath: String
	let message: String
}

struct WorkspaceFileTreeSnapshot: Equatable, Sendable
{
	let checkoutRoot: String
	let nodes: [WorkspaceFileNode]
	/// True for limits, unreadable directories, or entries that changed during enumeration.
	let isPartial: Bool
	let issues: [WorkspaceFileTreeIssue]
}

struct WorkspaceFileTextPreview: Equatable, Sendable
{
	let identity: WorkspaceFileIdentity
	let text: String
	let version: WorkspaceFileVersion
}

enum WorkspaceFilePreview: Equatable, Sendable
{
	case text(WorkspaceFileTextPreview)
	case binary
	case missing
	case unreadable(String)
	case oversized(byteCount: Int64)
	case symbolicLink
	case invalidPath
	case changed
}

struct WorkspaceFileLimits: Equatable, Sendable
{
	var maximumNodes = 10_000
	var maximumDepth = 64
	var maximumPreviewBytes = 1_048_576
}

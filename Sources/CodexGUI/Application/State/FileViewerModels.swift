import Foundation

struct FileLocation: Hashable, Sendable
{
	let root: String
	let relativePath: String

	init(
		root: String,
		relativePath: String
	)
	{
		self.root = URL(fileURLWithPath: root).standardizedFileURL.path
		self.relativePath = relativePath
	}

	var fileURL: URL
	{
		URL(fileURLWithPath: root).appendingPathComponent(relativePath)
	}

	static func == (lhs: FileLocation, rhs: FileLocation) -> Bool
	{
		lhs.root.utf8.elementsEqual(rhs.root.utf8)
			&& lhs.relativePath.utf8.elementsEqual(rhs.relativePath.utf8)
	}

	func hash(into hasher: inout Hasher)
	{
		hasher.combine(Data(root.utf8))
		hasher.combine(Data(relativePath.utf8))
	}
}

enum FileViewerFailure: Error, Equatable, Sendable
{
	case invalidPath
	case unavailable
	case unsupportedEncoding
	case binary
	case tooLarge
	case readOnly
	case conflict
	case cancelled
	case io(String)
}

struct FileDiskRevision: Equatable, Sendable
{
	let digest: String
	let byteCount: Int
}

enum FileViewerContent: Sendable, Equatable
{
	case text(String)
	case empty
	case image(Data)
	case pdf(Data)
	case unsupported
}

struct FileViewerRead: Sendable, Equatable
{
	let content: FileViewerContent
	let revision: FileDiskRevision
	let isReadOnly: Bool
}

struct FileViewerDirectoryEntry: Sendable, Equatable
{
	let location: FileLocation
	let isDirectory: Bool
	let isSymbolicLink: Bool

	var name: String
	{
		URL(fileURLWithPath: location.relativePath).lastPathComponent
	}
}

struct FileViewerSearchResult: Sendable, Equatable
{
	let location: FileLocation
	let lineNumber: Int
	let lineText: String
}

struct FileViewerSearchPage<Value: Sendable & Equatable>: Sendable, Equatable
{
	let results: [Value]
	let isTruncated: Bool
	let excludedDirectoryCount: Int

	init(
		results: [Value],
		isTruncated: Bool,
		excludedDirectoryCount: Int = 0
	)
	{
		self.results = results
		self.isTruncated = isTruncated
		self.excludedDirectoryCount = excludedDirectoryCount
	}
}

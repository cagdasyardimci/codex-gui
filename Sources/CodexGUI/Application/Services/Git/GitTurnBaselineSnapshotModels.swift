import Foundation

struct GitTurnBaselineRecord: Codable, Sendable
{
	var reference: GitTurnBaselineReference
	let entries: [GitTurnBaselineEntry]
	let indexManifest: Data
}

struct GitTurnBaselineEntry: Codable, Equatable, Sendable
{
	enum Kind: String, Codable, Sendable
	{
		case regular, symbolicLink, missing
	}
	let path: String
	let kind: Kind
	let executable: Bool
	let byteCount: Int
	let digest: String
}

struct GitTurnBaselineContent: Equatable, Sendable
{
	let entry: GitTurnBaselineEntry
	let bytes: Data
}

struct GitTurnBaselineTree: Equatable, Sendable
{
	let files: [GitTurnBaselineContent]
	let indexManifest: Data
	var byteCount: Int
	{
		files.reduce(
			0,
			{
				$0 + $1.bytes.count
			}
		)
	}
}

enum GitTurnBaselineReadError: Error
{
	case failure(GitComparisonFailure)
}

import CryptoKit
import Foundation

/// Reads exact comparison blobs without running Git filters or following workspace symlinks.
enum GitRichPreviewContent
{
	static let maximumBytes = 8 * 1024 * 1024

	static func blobID(for file: GitComparisonFile) -> String?
	{
		let metadata = file.patch.components(separatedBy: "\n").prefix
		{
			!$0.hasPrefix("@@ ")
		}
		guard !metadata.contains(where:
			{
				$0.split(separator: " ").last == "120000"
			}),
			let index = metadata.first(where:
				{
					$0.hasPrefix("index ")
				})
		else
		{
			return nil
		}
		let pair = index.dropFirst(6).split(separator: " ").first?
			.components(separatedBy: "..") ?? []
		guard pair.count == 2
		else
		{
			return nil
		}
		let value = pair[file.kind == .deleted ? 0 : 1]
		guard [40, 64].contains(value.count),
				value.allSatisfy(
				{
					$0.isHexDigit
				}
				), value.contains(where:
				{
					$0 != "0"
				})
		else
		{
			return nil
		}
		return value
	}

	static func read(
		file: GitComparisonFile,
		snapshot: GitComparisonSnapshot
	) async throws -> Data
	{
		let result: Result<Data, Error> = await GitSubprocessCancellation.detached
		{
			Result
			{
				guard let blob = blobID(for: file)
				else
				{
					throw GitComparisonFailure.repositoryChanged
				}
				let root = snapshot.request.repositoryRoot
				let stored = try GitCommandRunner.run(
					arguments: ["-C", root, "cat-file", "blob", blob],
					maximumBytes: maximumBytes
				)
				if stored.terminationStatus == 0
				{
					return stored.bytes
				}

				// A working-tree blob may not exist in Git's object database yet.
				guard file.kind != .deleted
				else
				{
					throw GitComparisonFailure.repositoryChanged
				}
				let directory = URL(fileURLWithPath: root).resolvingSymlinksInPath()
				let url = directory.appendingPathComponent(file.path).standardizedFileURL
				guard url.path.hasPrefix(directory.path + "/"),
						url.resolvingSymlinksInPath() == url
				else
				{
					throw GitComparisonFailure.repositoryChanged
				}
				let bytes: Data
				do
				{
					(bytes, _) = try ContainedFileAccess.read(
						FileLocation(
							root: directory.path,
							relativePath: file.path
						),
						maximumBytes: maximumBytes
					)
				}
				catch FileViewerFailure.tooLarge
				{
					throw GitComparisonFailure.oversized
				}
				catch is FileViewerFailure
				{
					throw GitComparisonFailure.repositoryChanged
				}
				let header = Data("blob \(bytes.count)\0".utf8)
				let digest: [UInt8]
				if blob.count == 40
				{
					var hash = Insecure.SHA1()
					hash.update(data: header)
					hash.update(data: bytes)
					digest = Array(hash.finalize())
				}
				else
				{
					var hash = SHA256()
					hash.update(data: header)
					hash.update(data: bytes)
					digest = Array(hash.finalize())
				}
				guard digest.map(
					{
						String(
							format: "%02x",
							$0
						)
					}
				).joined() == blob
				else
				{
					throw GitComparisonFailure.repositoryChanged
				}
				return bytes
			}
		}
		return try result.get()
	}
}

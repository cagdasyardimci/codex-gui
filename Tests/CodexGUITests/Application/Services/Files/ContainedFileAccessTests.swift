import Darwin
import Foundation
import Testing

@testable import CodexGUI

struct ContainedFileAccessTests
{
	@Test func readsOnlyBoundedRegularFilesInsideTheCapturedRoot() throws
	{
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("contained-file-\(UUID().uuidString)")
		try FileManager.default.createDirectory(
			at: root,
			withIntermediateDirectories: false
		)
		defer
		{
			try? FileManager.default.removeItem(at: root)
		}
		let bytes = Data("payload".utf8)
		try bytes.write(to: root.appendingPathComponent("file.txt"))
		let file = FileLocation(
			root: root.path,
			relativePath: "file.txt"
		)
		#expect(try ContainedFileAccess.read(
			file,
			maximumBytes: bytes.count
		).0 == bytes)
		#expect(throws: FileViewerFailure.tooLarge)
		{
			try ContainedFileAccess.read(
				file,
				maximumBytes: bytes.count - 1
			)
		}
		for path in ["../file.txt", "file.txt/..", "/file.txt", "file.txt\0suffix"]
		{
			#expect(throws: FileViewerFailure.self)
			{
				try ContainedFileAccess.read(
					FileLocation(
						root: root.path,
						relativePath: path
					),
					maximumBytes: 20
				)
			}
		}
		try FileManager.default.createSymbolicLink(
			at: root.appendingPathComponent("link"),
			withDestinationURL: root.appendingPathComponent("file.txt")
		)
		try FileManager.default.createSymbolicLink(
			at: root.appendingPathComponent("directory-link"),
			withDestinationURL: root
		)
		let pipe = root.appendingPathComponent("pipe")
		try #require(mkfifo(
			pipe.path,
			0o600
		) == 0)
		for path in ["link", "directory-link/file.txt", "pipe", ""]
		{
			#expect(throws: FileViewerFailure.self)
			{
				try ContainedFileAccess.read(
					FileLocation(
						root: root.path,
						relativePath: path
					),
					maximumBytes: 20
				)
			}
		}
	}
}

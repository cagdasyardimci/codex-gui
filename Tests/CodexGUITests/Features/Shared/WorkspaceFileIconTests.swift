import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct WorkspaceFileIconTests
{
	@Test func pathAssetsCoverSupportedFileKinds()
	{
		let examples: [(String, DesktopIcon)] = [
			("image.PNG", .fileImage),
			("notes.markdown", .fileDocument),
			("script.tsx", .fileCode),
			("table.csv", .fileSpreadsheet),
			("slides.key", .filePresentation),
			("recording.flac", .fileAudio),
			("clip.mov", .fileVideo),
			("archive.tar", .fileZip),
			("unknown.xyz", .fileBlank),
		]
		for (path, expected) in examples
		{
			let type = WorkspaceFileTypePresentation(relativePath: path)
			#expect(WorkspaceFileIcon.asset(
				for: type,
				relativePath: path
			) == expected)
		}
	}

	@Test func metadataPrecedesExtensionAndKeepsAccessibility()
	{
		let path = "Sources/Example.swift"
		let swift = WorkspaceFileIcon.image(
			relativePath: path,
			size: 18
		)
		#expect(swift.size == NSSize(
			width: 18,
			height: 18
		))
		#expect(!swift.isTemplate)
		#expect(swift.accessibilityDescription == "Swift source")

		let folder = WorkspaceFileIcon.image(
			relativePath: path,
			isDirectory: true,
			size: 18
		)
		#expect(folder.isTemplate)
		#expect(folder.accessibilityDescription == "Folder")
		#expect(WorkspaceFileIcon.asset(
			for: WorkspaceFileTypePresentation(
				relativePath: path,
				isDirectory: true
			),
			relativePath: path
		) == .folder)

		let link = WorkspaceFileIcon.image(
			relativePath: path,
			isDirectory: true,
			isSymbolicLink: true,
			size: 18
		)
		#expect(link.isTemplate)
		#expect(link.accessibilityDescription == "Symbolic link, preview unavailable")
		#expect(WorkspaceFileIcon.asset(
			for: WorkspaceFileTypePresentation(
				relativePath: path,
				isDirectory: true,
				isSymbolicLink: true
			),
			relativePath: path
		) == .link)
	}

	@Test func featureAdaptersShareFileArtwork()
	{
		let path = "Sources/Example.swift"
		let files = FileViewerIcons.fileImage(relativePath: path)
		let changes = GitReviewReferenceIcons.fileImage(relativePath: path)
		#expect(!files.isTemplate)
		#expect(!changes.isTemplate)
		#expect(files.accessibilityDescription == changes.accessibilityDescription)
		#expect(FileViewerIcons.image(for: WorkspaceFileTypePresentation(
			relativePath: path
		))?.isTemplate == false)
	}
}

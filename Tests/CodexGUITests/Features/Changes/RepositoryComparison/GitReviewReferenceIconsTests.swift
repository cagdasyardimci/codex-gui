import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct GitReviewReferenceIconsTests
{
	@Test func intrinsicColorIsReservedForSwiftAndDiffMode()
	{
		for kind in GitReviewReferenceIcons.Kind.allCases
		{
			let image = GitReviewReferenceIcons.image(
				kind,
				size: 20,
				accessibilityDescription: "Review control"
			)
			#expect(image.size == NSSize(
				width: 20,
				height: 20
			))
			#expect(image
				.isTemplate ==
				(kind != .swiftFile && kind != .displayMode && kind != .unifiedDisplayMode))
			#expect(image.accessibilityDescription == "Review control")
		}
	}

	@Test func swiftFileColorSurvivesHeaderAndTreeProjection()
	{
		let metadata = WorkspaceFileTypePresentation(relativePath: "Sources/Example.swift")
		let metadataImage = GitReviewReferenceIcons.fileImage(for: metadata)
		let pathImage = GitReviewReferenceIcons.fileImage(relativePath: "Sources/Example.swift")
		#expect(!metadataImage.isTemplate)
		#expect(!pathImage.isTemplate)
		#expect(metadataImage.accessibilityDescription == "Swift source")
		let folder = GitReviewReferenceIcons.fileImage(
			relativePath: "Sources.swift",
			isDirectory: true
		)
		#expect(folder.isTemplate)
		#expect(folder.accessibilityDescription == "Folder")
	}
}

import Foundation

/// Captured document identity and title for the outer Tools tab strip.
struct FileToolTabPresentation: Equatable
{
	let id: UUID
	let title: String
	let path: String
	let isPreview: Bool
	let isDirty: Bool
}

import AppKit

/// Installs prepared renderer artwork under one attachment budget, preserving exact source.
@MainActor
enum MarkdownRichBlockRenderer
{
	static func attachment(
		source: String,
		budget: inout MarkdownRichBlockBudget,
		preparedImages: MarkdownRichBlockImageCache.Images?,
		isDiagram: Bool = false
	) -> NSTextAttachment
	{
		guard let images = admittedImages(
			preparedImages,
			budget: &budget
		)
		else
		{
			return MarkdownRichAttachment(
				source: source,
				lightImage: nil,
				darkImage: nil
			)
		}
		return images.attachment(
			source: source,
			isDiagram: isDiagram
		)
	}

	static func admittedImages(
		_ images: MarkdownRichBlockImageCache.Images?,
		budget: inout MarkdownRichBlockBudget
	) -> MarkdownRichBlockImageCache.Images?
	{
		guard budget.beginBlock(), let images, budget.reservePixels(images.budgetPixelCost)
		else
		{
			return nil
		}
		return images
	}
}

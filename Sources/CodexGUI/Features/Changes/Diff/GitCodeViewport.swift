import Foundation

/// Horizontal source scrolling uses finite measured width and document height.
struct GitCodeViewport: Equatable
{
	static let textInset: CGFloat = 10
	static let minimumDocumentWidth: CGFloat = 240
	let documentSize: CGSize
	let containerSize: CGSize

	init(
		viewportWidth: CGFloat,
		measuredCodeWidth: CGFloat,
		documentHeight: CGFloat
	)
	{
		let finiteViewportWidth = viewportWidth.isFinite ? max(
			0,
			viewportWidth
		) : 0
		let finiteMeasuredCodeWidth = measuredCodeWidth.isFinite ? max(
			0,
			measuredCodeWidth
		) : 0
		let width = max(
			Self.minimumDocumentWidth,
			finiteViewportWidth,
			finiteMeasuredCodeWidth
		)
		let height = documentHeight.isFinite ? max(
			1,
			documentHeight
		) : 1
		documentSize = CGSize(
			width: width,
			height: height
		)
		containerSize = CGSize(
			width: width - 2 * Self.textInset,
			height: height
		)
	}
}

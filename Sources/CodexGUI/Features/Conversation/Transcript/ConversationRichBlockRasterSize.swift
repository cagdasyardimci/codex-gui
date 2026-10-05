import Foundation

/// Shared raster dimensions for rendering and retained rich-image estimates.
struct ConversationRichBlockRasterSize: Sendable
{
	static let scale: CGFloat = 2

	let width: Int
	let height: Int
	let pixelCount: Int

	init?(size: CGSize)
	{
		guard size.width.isFinite, size.height.isFinite,
				size.width > 0, size.height > 0
		else
		{
			return nil
		}
		let width = ceil(size.width * Self.scale)
		let height = ceil(size.height * Self.scale)
		let pixels = width * height
		// Bound conversions as well as multiplication before allocating a native bitmap.
		guard width.isFinite, height.isFinite, pixels.isFinite,
				width < CGFloat(Int.max), height < CGFloat(Int.max),
				pixels > 0, pixels < CGFloat(Int.max)
		else
		{
			return nil
		}
		self.width = Int(width)
		self.height = Int(height)
		let count = self.width.multipliedReportingOverflow(by: self.height)
		guard !count.overflow
		else
		{
			return nil
		}
		pixelCount = count.partialValue
	}
}

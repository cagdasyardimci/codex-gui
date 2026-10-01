import Foundation

/// Bounds retained native images across every rich block in one prepared message.
struct ConversationRichBlockBudget: Sendable
{
	private var remainingPixels: Int
	private var remainingBlocks: Int

	init(
		maximumPixels: Int = 2_000_000,
		maximumBlocks: Int = 32
	)
	{
		remainingPixels = max(
			0,
			maximumPixels
		)
		remainingBlocks = max(
			0,
			maximumBlocks
		)
	}

	mutating func beginBlock() -> Bool
	{
		guard remainingBlocks > 0
		else
		{
			return false
		}
		remainingBlocks -= 1
		return true
	}

	mutating func reservePixels(_ count: Int) -> Bool
	{
		guard count > 0, count <= remainingPixels
		else
		{
			return false
		}
		remainingPixels -= count
		return true
	}

	mutating func releasePixels(_ count: Int)
	{
		remainingPixels += count
	}

	static func estimatedPixels(for size: CGSize) -> Int
	{
		let pixels = ceil(size.width * 2) * ceil(size.height * 2)
		guard pixels.isFinite, pixels > 0, pixels < CGFloat(Int.max)
		else
		{
			return 0
		}
		return Int(pixels)
	}
}

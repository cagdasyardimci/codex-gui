import Foundation
import Testing

@testable import CodexGUI

struct ConversationRichBlockBudgetTests
{
	@Test(arguments: [
		CGSize(
			width: CGFloat.nan,
			height: 1
		),
		CGSize(
			width: 1,
			height: CGFloat.infinity
		),
		CGSize(
			width: 0,
			height: 1
		),
		CGSize(
			width: -1,
			height: -1
		),
		CGSize(
			width: CGFloat(Int.max),
			height: 1
		),
		CGSize(
			width: CGFloat.greatestFiniteMagnitude,
			height: 1
		),
		CGSize(
			width: 2_000_000_000,
			height: 2_000_000_000
		)
	])
	func invalidRasterSizesCannotConsumeBudget(_ size: CGSize)
	{
		let estimate = ConversationRichBlockBudget.estimatedPixels(for: size)
		#expect(estimate == 0)
		var budget = ConversationRichBlockBudget(maximumPixels: 1)
		let invalidReservation = budget.reservePixels(estimate)
		let validReservation = budget.reservePixels(1)
		#expect(!invalidReservation)
		#expect(validReservation)
	}
}

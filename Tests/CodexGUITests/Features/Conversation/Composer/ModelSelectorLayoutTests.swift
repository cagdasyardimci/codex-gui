import AppKit
import Testing

@testable import CodexGUI

struct ModelSelectorLayoutTests
{
	@Test @MainActor func openingPickerKeepsAnchorWidthUntilDismissal()
	{
		let button = ModelEffortSelectionButton(frame: .zero)
		let fallbackWidth = button.intrinsicContentSize.width
		button.update(
			summary: nil,
			fastMode: false,
			isPickerPresented: true
		)
		#expect(button.intrinsicContentSize.width == fallbackWidth)
		let summary = "A long model name Extra High"
		button.update(
			summary: summary,
			fastMode: true,
			isPickerPresented: false
		)
		let closedWidth = button.intrinsicContentSize.width
		button.update(
			summary: summary,
			fastMode: true,
			isPickerPresented: true
		)
		#expect(button.title == "Select effort")
		#expect(button.intrinsicContentSize.width == closedWidth)
		#expect(button.accessibilityLabel() == "Model and effort: " + summary)

		let replacement = "An even longer model name Extra High"
		button.update(
			summary: replacement,
			fastMode: true,
			isPickerPresented: true
		)
		#expect(button.intrinsicContentSize.width == closedWidth)
		button.update(
			summary: "Short model Low",
			fastMode: true,
			isPickerPresented: true
		)
		#expect(button.intrinsicContentSize.width == closedWidth)
		button.update(
			summary: replacement,
			fastMode: true,
			isPickerPresented: false
		)
		let replacementWidth = button.intrinsicContentSize.width
		#expect(replacementWidth > closedWidth)
		button.update(
			summary: replacement,
			fastMode: true,
			isPickerPresented: true
		)
		#expect(button.intrinsicContentSize.width == replacementWidth)
	}

	@Test func modelRequestAndAllocatedTextSpaceResolveDifferentLimits()
	{
		#expect(!LayoutTokens.ModelSelector(maximumWidth: 0).isValid)
		#expect(!LayoutTokens.ModelSelector(chevronSize: CGSize(
			width: CGFloat.nan,
			height: 16
		))
		.isValid)
		let enlarged = LayoutTokens.ModelSelector(chevronSize: CGSize(
			width: 24,
			height: 24
		))
		let bounds = CGRect(
			x: 0,
			y: 0,
			width: 280,
			height: 28
		)
		let title = CGSize(
			width: 240,
			height: 16
		)
		#expect(ModelSelectorLayout().fits(controlHeight: 28))
		#expect(ModelSelectorLayout(metrics: enlarged).fits(controlHeight: 28))
		#expect(!ModelSelectorLayout(metrics: enlarged).fits(controlHeight: 20))
		#expect(ModelSelectorLayout().requestedWidth(
			titleWidth: 240,
			displaysBolt: true
		) == 294)
		#expect(ModelSelectorLayout(metrics: enlarged).requestedWidth(
			titleWidth: 240,
			displaysBolt: true
		) == 300)
		let baseline = ModelSelectorLayout().content(
			in: bounds,
			titleSize: title,
			displaysBolt: true
		)
		let changed = ModelSelectorLayout(metrics: enlarged).content(
			in: bounds,
			titleSize: title,
			displaysBolt: true
		)
		#expect(baseline.textRect.width == 226)
		#expect(changed.textRect.width == 218)
		#expect(changed.chevronRect.size == CGSize(
			width: 24,
			height: 24
		))
		#expect(changed.chevronRect.midY == bounds.midY)
	}
}

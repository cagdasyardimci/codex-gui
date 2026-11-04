import AppKit
import CoreText
import Testing

@testable import CodexGUI

@MainActor
struct PopupTypographyTests
{

	@Test func configurationDescriptionHasRoomForItsMeasuredLineBox() throws
	{
		let row = SettingsChoiceMenuRow(
			title: "On request",
			icon: nil,
			checked: true,
			detail: "Ask when needed",
			showsCheckbox: false,
			detailRole: TypographyTokens.Settings.choiceDescription
		)
		row.frame = NSRect(
			x: 0,
			y: 0,
			width: 360,
			height: row.rowHeight
		)
		row.layoutSubtreeIfNeeded()
		try expectFont(
			row.subtitleLabel.font,
			size: TypographyConfiguration.current.uiSize - 1,
			weight: 430
		)
		let font = try #require(row.subtitleLabel.font)
		#expect(row.subtitleLabel.frame.height >= font.ascender - font.descender)
		#expect(row.subtitleLabel.frame.maxY <= row.bounds.maxY)
	}

	private func expectFont(
		_ value: NSFont?,
		size: CGFloat,
		weight: Int
	) throws
	{
		let font = try #require(value)
		#expect(font.pointSize == size)
		let variations = CTFontCopyVariation(font as CTFont) as? [NSNumber: NSNumber]
		let axes = try #require(CTFontCopyVariationAxes(font as CTFont) as? [[String: Any]])
		let weightAxis = try #require(axes.first
		{
			($0[kCTFontVariationAxisIdentifierKey as String] as? NSNumber)?.intValue == 0x77676874
		})
		let resolved = variations?[NSNumber(value: 0x77676874)]
			?? (weightAxis[kCTFontVariationAxisDefaultValueKey as String] as? NSNumber)
		#expect(resolved?.intValue == weight)
		#expect(!CTFontGetSymbolicTraits(font as CTFont).contains(.traitItalic))
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap(descendants)
	}
}

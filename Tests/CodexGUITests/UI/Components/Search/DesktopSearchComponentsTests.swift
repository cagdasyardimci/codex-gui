import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct DesktopSearchComponentsTests
{
	@Test func messageSheetOwnsLoadMoreAndCloseActionsWithoutResettingQuery() throws
	{
		_ = NSApplication.shared
		let component = DesktopSearchSheetView(presentation: .messages)
		component.query.stringValue = "retained query"
		var loads = 0
		var closes = 0
		component.onLoadMore =
		{
			loads += 1
		}
		component.onClose =
		{
			closes += 1
		}
		let load = try #require(button(
			"Load more conversation history into message search",
			in: component
		))
		let close = try #require(button(
			"Close message search",
			in: component
		))
		#expect(load is DesktopStyledButton)
		#expect(close is DesktopStyledButton)
		for button in [load, close]
		{
			let styled = try #require(button as? DesktopStyledButton)
			#expect(styled.presentation == .secondary)
			#expect(styled.font == AppKitFontResolver.font(TypographyTokens.Button.compact))
			let bounds = NSRect(
				origin: .zero,
				size: styled.intrinsicContentSize
			)
			#expect(bounds.contains(styled.contentLayout(in: bounds).title))
		}
		#expect(load.isHidden)
		component.canLoadMore = true
		component.isLoading = true
		#expect(!load.isHidden)
		#expect(!load.isEnabled)
		component.isLoading = false
		#expect(load.dispatchConfiguredAction())
		#expect(close.dispatchConfiguredAction())
		#expect(loads == 1)
		#expect(closes == 1)
		#expect(component.query.stringValue == "retained query")
	}

	@Test func attachmentResultPreservesNativeMetricsAndRoutesTheExactPath() throws
	{
		_ = NSApplication.shared
		let receiver = SearchAttachmentReceiver()
		let path = "Sources/folder with spaces=value.swift"
		let result = DesktopSearchResultButton.attachment(
			path: path,
			target: receiver,
			action: #selector(SearchAttachmentReceiver.choose(_:))
		)
		let native = NSButton(
			title: path,
			target: nil,
			action: nil
		)
		native.bezelStyle = .inline
		native.alignment = .left
		#expect(result.title == path)
		#expect(result.frame.size == native.frame.size)
		#expect(result.intrinsicContentSize == native.intrinsicContentSize)
		#expect(result.font == native.font)
		#expect(result.bezelStyle == native.bezelStyle)
		#expect(result.alignment == native.alignment)
		#expect(result.cell?.lineBreakMode == native.cell?.lineBreakMode)
		let bounds = NSRect(
			origin: .zero,
			size: native.intrinsicContentSize
		)
		#expect(result.cell?.titleRect(forBounds: bounds) == native.cell?
			.titleRect(forBounds: bounds))
		#expect(result.accessibilityLabel() == "Attach project file \(path)")
		#expect(result.dispatchConfiguredAction())
		#expect(receiver.chosenPath == path)
	}

	private func button(
		_ label: String,
		in view: NSView
	) -> NSButton?
	{
		for child in view.subviews
		{
			if let button = child as? NSButton, button.accessibilityLabel() == label
			{
				return button
			}
			if let result = button(
				label,
				in: child
			)
			{
				return result
			}
		}
		return nil
	}
}

@MainActor
private final class SearchAttachmentReceiver: NSObject
{
	var chosenPath: String?

	@objc func choose(_ sender: NSButton)
	{
		chosenPath = sender.identifier?.rawValue
	}
}

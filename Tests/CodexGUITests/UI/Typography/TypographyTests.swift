import AppKit
import Testing

@testable import CodexGUI

struct TypographyTests
{
	static let measurements: [CGFloat] = [11, 13, 14, 15, 16]
	@Test(arguments: measurements)
	func measuredUIHierarchy(sample: CGFloat)
	{
		let config = TypographyConfiguration(uiSize: sample)
		#expect(TypographyTokens.Transcript.prose.resolved(using: config).size == sample)
		#expect(TypographyTokens.UI.small.resolved(using: config).size == sample - 1)
		#expect(TypographyTokens.Transcript.heading(level: 1).resolved(using: config)
			.size == sample * 1.5)
		#expect(TypographyTokens.Transcript.heading(level: 2).resolved(using: config)
			.size == sample * 1.25)
		#expect(TypographyTokens.Transcript.heading(level: 3).resolved(using: config)
			.size == sample * 1.125)
		#expect(TypographyTokens.Transcript.heading(level: 3).resolved(using: config)
			.lineHeight == sample * 1.75)
		#expect(TypographyTokens.Transcript.prose.resolved(using: config)
			.lineHeight == sample * 1.625)
		#expect(TypographyTokens.Transcript.inlineCode.resolved(using: config)
			.size == sample * 0.92)
		#expect(TypographyTokens.Code.source.resolved(using: config).size == 12)
		let row = TypographyTokens.Connections.rowLabel.resolved(using: config)
		#expect(abs((row.lineHeight ?? 0) - (sample - 1) * (10.0 / 7)) < 0.000001)
		#expect(TypographyTokens.Sources.provider.resolved(using: config).lineHeight == row
			.lineHeight)
		#expect(TypographyTokens.Button.value.resolved(using: config).size == sample - 1)
		#expect(TypographyTokens.Button.value.resolved(using: config).lineHeight == 20)
		#expect(TypographyTokens.Button.dialog.resolved(using: config).lineHeight == 18)
		#expect(TypographyTokens.Button.value.weight == .text)
		#expect(TypographyTokens.Button.dialog.weight == .text)
		#expect(TypographyTokens.Button.regular.weight == .regular)
	}

	@Test func independentCodeBaseAndTableFloor()
	{
		let smallCode = TypographyConfiguration(
			uiSize: 14,
			codeSize: 10
		)
		let largeCode = TypographyConfiguration(
			uiSize: 14,
			codeSize: 16
		)
		#expect(TypographyTokens.Transcript.table.resolved(using: smallCode).size == 12.25)
		#expect(TypographyTokens.Transcript.table.resolved(using: largeCode).size == 16)
		#expect(TypographyTokens.Code.diff.resolved(using: largeCode).lineHeight == 28.8)
		#expect(TypographyTokens.Code.source.resolved(using: largeCode).lineHeight == 29)
		#expect(TypographyTokens.FileSearch.source.resolved(using: largeCode).size == 13)
		#expect(TypographyTokens.FileMarkdown.inlineCode.resolved(using: largeCode).size == 14)
		#expect(TypographyTokens.Transcript.codeHeader.resolved(using: largeCode).size == 13)
	}

	@Test func invalidPreferencesAreNormalized()
	{
		#expect(TypographyConfiguration(
			uiSize: .nan,
			contentSize: .nan,
			codeSize: .infinity
		) == .standard)
		#expect(TypographyConfiguration(
			uiSize: 0,
			contentSize: 100,
			codeSize: 100
		) == TypographyConfiguration(
			uiSize: 11,
			contentSize: 24,
			codeSize: 24
		))
		#expect(TypographyConfiguration(
			uiSize: 13.6,
			codeSize: 11.2
		) == TypographyConfiguration(
			uiSize: 14,
			codeSize: 11
		))
	}

	@Test func filePreviewFollowsUIWhilePageContentAndCodeRemainIndependent()
	{
		let config = TypographyConfiguration(
			uiSize: 11,
			contentSize: 24,
			codeSize: 8
		)
		#expect(TypographyTokens.FileMarkdown.prose.resolved(using: config).size == 11)
		#expect(TypographyTokens.FileMarkdown.inlineCode.resolved(using: config).size == 11)
		#expect(TypographyTokens.FileMarkdown.heading(level: 1).resolved(using: config).size == 19)
		#expect(TypographyTokens.Transcript.prose.resolved(using: config).size == 11)
		#expect(TypographyTokens.Code.source.resolved(using: config).size == 8)
	}
}

@MainActor
struct TypographyBindingTests
{
	@Test func legacyPreferencesGainContentSizeWithoutChangingOtherScopes() throws
	{
		let name = "TypographyMigration.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: name))
		defer
		{
			defaults.removePersistentDomain(forName: name)
		}
		defaults.set(
			["ui": 13, "code": 16],
			forKey: "appearance.typography"
		)
		let preferences = TypographyPreferences(defaults: defaults)
		#expect(preferences.configuration == TypographyConfiguration(
			uiSize: 13,
			codeSize: 16
		))
		preferences.save(
			TypographyConfiguration(
				uiSize: 13,
				contentSize: 21,
				codeSize: 16
			),
			center: NotificationCenter()
		)
		#expect(TypographyPreferences(defaults: defaults).configuration.contentSize == 21)
		#expect(defaults.dictionary(forKey: "appearance.typography")?["ui"] as? Int == 13)
		#expect(defaults.dictionary(forKey: "appearance.typography")?["code"] as? Int == 16)
	}

	@Test func menuTypographyRefreshResizesRowsAndPreservesSelectionAndAction() throws
	{
		let center = NotificationCenter()
		let state = ConfigurationState()
		state.value = TypographyConfiguration(uiSize: 11)
		let parent = NSView(frame: NSRect(
			x: 0,
			y: 0,
			width: 400,
			height: 300
		))
		let row = DesktopMenuRow(
			content: .init(
				title: "Selected model",
				subtitle: "Supporting text",
				indicator: .checkmark,
				checked: true
			),
			configuration:
			{
				state.value
			},
			center: center
		)
		row.translatesAutoresizingMaskIntoConstraints = false
		parent.addSubview(row)
		NSLayoutConstraint.activate([
			row.widthAnchor.constraint(equalToConstant: 360),
			row.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
			row.topAnchor.constraint(equalTo: parent.topAnchor)
		])
		parent.layoutSubtreeIfNeeded()
		let smallHeight = row.frame.height
		var invocations = 0
		row.onInvoke =
		{
			invocations += 1
		}
		for size: CGFloat in [16, 11]
		{
			state.value = TypographyConfiguration(uiSize: size)
			center.post(
				name: TypographyPreferences.didChange,
				object: nil
			)
			parent.layoutSubtreeIfNeeded()
			let height = try #require(row.constraints.first
			{
				$0.firstAttribute == .height
			})
			#expect(height.constant == row.rowHeight)
			// Auto Layout aligns the fractional typography request to the device pixel grid.
			#expect(abs(row.frame.height - row.rowHeight) <= 0.5)
			#expect(size == 16 ? row.frame
				.height > smallHeight : abs(row.frame.height - smallHeight) < 0.01)
			#expect(row.titleLabel.font?.pointSize == size - 1)
			let font = try #require(row.subtitleLabel.font)
			#expect(row.subtitleLabel.frame.height >= font.ascender - font.descender)
			#expect(row.subtitleLabel.frame.maxY <= row.bounds.maxY)
			#expect(row.checked)
			#expect(row.titleLabel.stringValue == "Selected model")
		}
		#expect(row.sendAction(
			row.action,
			to: row.target
		))
		#expect(invocations == 1)
	}

	@Test func typographyRefreshKeepsSidebarActionsIconOnly()
	{
		let center = NotificationCenter()
		let state = ConfigurationState()
		for role in [SidebarIconButton.Role.refresh, .search, .add, .projectInfo, .projectNewChat]
		{
			let button = SidebarIconButton(role: role)
			let label = button.accessibilityLabel()
			let image = button.image
			button.setTypographyRole(
				TypographyTokens.UI.small,
				configuration:
				{
					state.value
				},
				center: center
			)
			#expect(button.imagePosition == .imageOnly)
			state.value = TypographyConfiguration(
				uiSize: 16,
				codeSize: 12
			)
			center.post(
				name: TypographyPreferences.didChange,
				object: nil
			)
			#expect(button.imagePosition == .imageOnly)
			state.value = TypographyConfiguration(
				uiSize: 14,
				codeSize: 16
			)
			center.post(
				name: TypographyPreferences.didChange,
				object: nil
			)
			#expect(button.imagePosition == .imageOnly)
			#expect(button.image === image)
			#expect(button.accessibilityLabel() == label)
		}
	}

	@Test func liveBindingPreservesControlContentAndButtonState() throws
	{
		let center = NotificationCenter()
		let state = ConfigurationState()
		let button = NSButton(
			checkboxWithTitle: "Keep selected",
			target: nil,
			action: nil
		)
		button.state = .on
		button.setTypographyRole(
			TypographyTokens.UI.small,
			configuration:
			{
				state.value
			},
			center: center
		)
		let field = NSTextField(labelWithString: "Retained value")
		field.setTypographyRole(
			TypographyTokens.UI.body,
			configuration:
			{
				state.value
			},
			center: center
		)
		state.value = TypographyConfiguration(
			uiSize: 16,
			codeSize: 10
		)
		center.post(
			name: TypographyPreferences.didChange,
			object: nil
		)
		#expect(button.state == .on)
		#expect(button.title == "Keep selected")
		#expect(button.font?.pointSize == 15)
		#expect(field.stringValue == "Retained value")
		#expect(field.font?.pointSize == 16)
		#expect((field.attributedStringValue.attribute(
			.font,
			at: 0,
			effectiveRange: nil
		) as? NSFont)?.pointSize == 16)
	}

	@Test func appearanceActionsPersistIndependentBases() throws
	{
		let name = "TypographyTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: name))
		defer
		{
			defaults.removePersistentDomain(forName: name)
		}
		let preferences = TypographyPreferences(defaults: defaults)
		#expect(preferences.configuration == .standard)
		let page = SettingsAppearancePage(
			preferences: preferences,
			center: NotificationCenter()
		)
		page.uiSizeField.integerValue = 13
		let action = try #require(page.uiSizeField.action)
		#expect(page.uiSizeField.sendAction(
			action,
			to: page.uiSizeField.target
		))
		#expect(TypographyPreferences(defaults: defaults)
			.configuration == TypographyConfiguration(uiSize: 13))
		page.codeSizeField.integerValue = 16
		let codeAction = try #require(page.codeSizeField.action)
		#expect(page.codeSizeField.sendAction(
			codeAction,
			to: page.codeSizeField.target
		))
		#expect(preferences.configuration == TypographyConfiguration(
			uiSize: 13,
			codeSize: 16
		))
		page.contentSizeField.integerValue = 20
		let contentAction = try #require(page.contentSizeField.action)
		#expect(page.contentSizeField.sendAction(
			contentAction,
			to: page.contentSizeField.target
		))
		#expect(TypographyPreferences(defaults: defaults).configuration == TypographyConfiguration(
			uiSize: 13,
			contentSize: 20,
			codeSize: 16
		))
		let first = TranscriptPreparationCoordinator.ContentKey(
			body: "Same text",
			markdown: true,
			typography: .standard
		)
		let changed = TranscriptPreparationCoordinator.ContentKey(
			body: "Same text",
			markdown: true,
			typography: preferences.configuration
		)
		#expect(first != changed)
		let contentOnly = TranscriptPreparationCoordinator.ContentKey(
			body: "Same text",
			markdown: true,
			typography: TypographyConfiguration(contentSize: 20)
		)
		#expect(first != contentOnly)
	}

	@Test func markdownResolvesContextBeforeInlineScaling() throws
	{
		let config = TypographyConfiguration(
			uiSize: 13,
			codeSize: 16
		)
		let heading = MarkdownTextStyle(
			heading: 1,
			code: true
		)
		#expect(abs(MarkdownAttributedStringRenderer.typography(for: heading)
				.resolved(using: config)
				.size - 19.5 * 0.92) < 0.000001)
		let table = MarkdownTextStyle(
			code: true,
			tableCell: MarkdownTableCell(
				tableID: 0,
				row: 1,
				column: 0,
				columnCount: 1,
				columnSpan: 1,
				rowSpan: 1,
				alignment: .left,
				header: false
			)
		)
		#expect(MarkdownAttributedStringRenderer.typography(for: table).resolved(using: config)
			.size == 16 * 0.92)
		let source = "# Heading `inline`\n\nBody `inline`\n\n"
			+ "| A | B |\n| - | - |\n| Cell | Value |\n\n```swift\nlet x = 1\n```"
		let parsed = MarkdownContentParser.parse(
			source,
			markdown: true
		)
		let file = FileMarkdownStyling
			.apply(to: MarkdownAttributedStringRenderer.render(parsed.runs))
		let bodyInline = (file.string as NSString).range(
			of: "inline",
			options: .backwards
		)
		#expect((file.attribute(
			.font,
			at: bodyInline.location,
			effectiveRange: nil
		) as? NSFont)?
			.pointSize == TypographyConfiguration.current.uiSize)
		let cell = (file.string as NSString).range(of: "Cell")
		#expect((file.attribute(
			.font,
			at: cell.location,
			effectiveRange: nil
		) as? NSFont)?
			.pointSize == TypographyConfiguration.current.uiSize)
		let code = (file.string as NSString).range(of: "let x")
		#expect((file.attribute(
			.font,
			at: code.location,
			effectiveRange: nil
		) as? NSFont)?
			.pointSize == TypographyConfiguration.current.codeSize)
	}

	@Test func nativeLineBoxesAccommodateGlyphMetrics() throws
	{
		let role = TypographyTokens.Composer.editor
		let config = TypographyConfiguration(uiSize: 16)
		let attributes = AppKitFontResolver.textAttributes(
			role,
			configuration: config
		)
		let font = try #require(attributes[.font] as? NSFont)
		let paragraph = try #require(attributes[.paragraphStyle] as? NSParagraphStyle)
		#expect(paragraph.minimumLineHeight >= font.ascender - font.descender + font.leading)
	}
}

@MainActor
private final class ConfigurationState
{
	var value = TypographyConfiguration.standard
}

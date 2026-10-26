import AppKit

/// Complete terminal output presentation; callers provide command data and expansion state.
@MainActor
final class ConversationTerminalCard: NSView
{
	struct ReadingPosition
	{
		let origin: NSPoint
		let selection: NSRange
	}

	private var pendingOutputReadingPosition: ReadingPosition?
	private var command: ConversationCommand?
	private var isExpanded = false
	private static let minimumShellHeight: CGFloat = 100
	private static let maximumShellSampleLength = 8000
	private static let maximumShellHeight: CGFloat = 218
	private static let terminalFont = NSFont(
		name: "Menlo-Regular",
		size: 13
	)
		?? NSFont.monospacedSystemFont(
			ofSize: 13,
			weight: .regular
		)
	private static let terminalLineSpacing: CGFloat = 3
	private static let terminalLineHeight = NSLayoutManager().defaultLineHeight(for: terminalFont)
		+ terminalLineSpacing
	private var shellHeightConstraint: NSLayoutConstraint?
	private var commandHeightConstraint: NSLayoutConstraint?
	private let bodyView = NSView()
	private let commandLabel = NSTextField(labelWithString: "")
	private let commandLine = NSView()
	private let shellStatusLabel = NSTextField(labelWithString: "")
	private let output = NSTextView()
	private let scroll = ConversationTerminalScrollView()
	private let copyCommandButton = ConversationTerminalCopyButton()
	private let copyOutputButton = ConversationTerminalCopyButton()

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		let card = DesktopOutputCard(
			title: "Shell",
			presentation: .terminal,
			body: bodyView
		)
		AppKitLayout.pin(
			card,
			to: self,
			inset: 0
		)
		configureShellOutput()
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func configure(
		_ command: ConversationCommand?,
		expanded: Bool,
		preserving position: ReadingPosition?
	)
	{
		self.command = command
		isExpanded = expanded && command != nil
		guard isExpanded, let command
		else
		{
			clearPresentation()
			return
		}
		commandLabel.attributedStringValue = Self.commandText(command.command)
		commandLabel.toolTip = command.command
		if position != nil, command.output.hasPrefix(output.string)
		{
			let length = (output.string as NSString).length
			output.textStorage?.replaceCharacters(
				in: NSRange(
					location: length,
					length: 0
				),
				with: (command.output as NSString).substring(from: length)
			)
		}
		else
		{
			output.string = command.output
		}
		pendingOutputReadingPosition = position ?? ReadingPosition(
			origin: .zero,
			selection: NSRange(
				location: 0,
				length: 0
			)
		)
		output.setAccessibilityLabel("Shell output")
		shellStatusLabel.stringValue = Self.shellStatus(command)
		shellStatusLabel.toolTip = Self.metadata(command)
		copyCommandButton.isEnabled = !command.command.isEmpty
		copyOutputButton.isEnabled = !command.output.isEmpty
		needsLayout = true
	}

	func resetCopyInteraction()
	{
		copyCommandButton.resetHover()
		copyOutputButton.resetHover()
	}

	func reset()
	{
		command = nil
		isExpanded = false
		resetCopyInteraction()
		clearPresentation()
	}

	private func clearPresentation()
	{
		pendingOutputReadingPosition = nil
		output.string = ""
		output.setSelectedRange(NSRange(
			location: 0,
			length: 0
		))
		commandLabel.stringValue = ""
		copyCommandButton.isEnabled = false
		copyOutputButton.isEnabled = false
	}

	func readingPosition() -> ReadingPosition?
	{
		guard isExpanded
		else
		{
			return nil
		}
		return pendingOutputReadingPosition ?? ReadingPosition(
			origin: scroll.contentView.bounds.origin,
			selection: output.selectedRange()
		)
	}

	func restoreReadingPosition(_ position: ReadingPosition)
	{
		guard isExpanded
		else
		{
			return
		}
		pendingOutputReadingPosition = position
		needsLayout = true
	}

	override func layout()
	{
		updateMeasuredGeometry(width: bounds.width)
		super.layout()
		updateOutputDocumentSize()
		applyPendingOutputReadingPosition()
	}

	func layoutContent(width: CGFloat)
	{
		updateMeasuredGeometry(width: width)
		layoutSubtreeIfNeeded()
		updateOutputDocumentSize()
		applyPendingOutputReadingPosition()
	}

	private func updateMeasuredGeometry(width: CGFloat)
	{
		guard isExpanded, let command, width > 0
		else
		{
			return
		}
		let previewHeight = Self.commandHeight(
			command.command,
			width: width
		)
		if commandHeightConstraint?.constant != previewHeight
		{
			commandHeightConstraint?.constant = previewHeight
		}
		let cardHeight = Self.height(
			command: command,
			width: width
		)
		if shellHeightConstraint?.constant != cardHeight
		{
			shellHeightConstraint?.constant = cardHeight
		}
	}

	func writeCommand(to pasteboard: NSPasteboard)
	{
		guard let command
		else
		{
			return
		}
		write(
			command.command,
			to: pasteboard
		)
	}

	func writeOutput(to pasteboard: NSPasteboard)
	{
		guard let command
		else
		{
			return
		}
		write(
			command.output,
			to: pasteboard
		)
	}

	private func write(
		_ text: String,
		to pasteboard: NSPasteboard
	)
	{
		pasteboard.clearContents()
		pasteboard.setString(
			text,
			forType: .string
		)
	}

	@objc private func copyCommand()
	{
		writeCommand(to: .general)
	}

	@objc private func copyOutput()
	{
		writeOutput(to: .general)
	}

	private func configureShellOutput()
	{
		shellHeightConstraint = heightAnchor
			.constraint(equalToConstant: Self.minimumShellHeight)
		shellHeightConstraint?.isActive = true
		shellStatusLabel.font = .systemFont(ofSize: 13)
		shellStatusLabel.textColor = AppKitColorTokens.terminalMutedText
		shellStatusLabel.alignment = .right
		shellStatusLabel.lineBreakMode = .byTruncatingTail
		output.isEditable = false
		output.isSelectable = true
		output.drawsBackground = false
		output.font = Self.terminalFont
		output.textColor = AppKitColorTokens.terminalText
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineSpacing = Self.terminalLineSpacing
		output.defaultParagraphStyle = paragraph
		output.textContainerInset = NSSize(
			width: 0,
			height: 3
		)
		output.textContainer?.lineFragmentPadding = 0
		output.isVerticallyResizable = true
		output.isHorizontallyResizable = true
		output.autoresizingMask = []
		output.maxSize = NSSize(
			width: CGFloat.greatestFiniteMagnitude,
			height: CGFloat.greatestFiniteMagnitude
		)
		output.textContainer?.widthTracksTextView = false
		output.textContainer?.containerSize = output.maxSize
		scroll.drawsBackground = false
		scroll.hasVerticalScroller = true
		scroll.hasHorizontalScroller = true
		scroll.autohidesScrollers = true
		scroll.scrollerStyle = .overlay
		scroll.documentView = output
		commandLabel.font = output.font
		commandLabel.textColor = AppKitColorTokens.terminalText
		commandLabel.isSelectable = true
		commandLabel.lineBreakMode = .byWordWrapping
		commandLabel.maximumNumberOfLines = 2
		commandLabel.cell?.truncatesLastVisibleLine = true
		commandLabel.clipsToBounds = true
		commandLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		commandLabel.setAccessibilityLabel("Shell command")
		commandLabel.translatesAutoresizingMaskIntoConstraints = false
		commandLine.addSubview(commandLabel)
		commandHeightConstraint = commandLine.heightAnchor.constraint(equalToConstant: 24)
		commandHeightConstraint?.isActive = true
		NSLayoutConstraint.activate([
			commandLabel.leadingAnchor.constraint(equalTo: commandLine.leadingAnchor),
			commandLabel.trailingAnchor.constraint(
				equalTo: commandLine.trailingAnchor,
				constant: -28
			),
			commandLabel.topAnchor.constraint(equalTo: commandLine.topAnchor),
			commandLabel.bottomAnchor.constraint(equalTo: commandLine.bottomAnchor)
		])
		let shellStack = AppKitLayout.verticalStack(
			[commandLine, scroll, shellStatusLabel],
			spacing: 8,
			alignment: .leading
		)
		AppKitLayout.pin(
			shellStack,
			to: bodyView,
			inset: 0
		)
		commandLine.widthAnchor.constraint(equalTo: shellStack.widthAnchor).isActive = true
		scroll.widthAnchor.constraint(equalTo: shellStack.widthAnchor).isActive = true
		scroll.setContentHuggingPriority(
			.defaultLow,
			for: .vertical
		)
		shellStatusLabel.widthAnchor.constraint(equalTo: shellStack.widthAnchor).isActive = true
		configureShellCopyButton(
			copyCommandButton,
			label: "Copy command",
			action: #selector(copyCommand),
			anchor: commandLine
		)
		configureShellCopyButton(
			copyOutputButton,
			label: "Copy output",
			action: #selector(copyOutput),
			anchor: scroll
		)
	}

	private func configureShellCopyButton(
		_ button: ConversationTerminalCopyButton,
		label: String,
		action: Selector,
		anchor: NSView
	)
	{
		button.configure(
			label: label,
			target: self,
			action: action
		)
		button.translatesAutoresizingMaskIntoConstraints = false
		bodyView.addSubview(button)
		NSLayoutConstraint.activate([
			button.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
			button.topAnchor.constraint(equalTo: anchor.topAnchor)
		])
	}

	private func applyPendingOutputReadingPosition()
	{
		guard let position = pendingOutputReadingPosition,
				scroll.contentSize.width > 0, scroll.contentSize.height > 0,
				let container = output.textContainer, let manager = output.layoutManager
		else
		{
			return
		}
		manager.ensureLayout(for: container)
		// Finish document and clip geometry before restoring the reader's offset.
		// Text storage updates can schedule a later resize of the scroll document.
		output.layoutSubtreeIfNeeded()
		scroll.layoutSubtreeIfNeeded()
		let textLength = (output.string as NSString).length
		let location = min(
			position.selection.location,
			textLength
		)
		let length = min(
			position.selection.length,
			textLength - location
		)
		output.setSelectedRange(NSRange(
			location: location,
			length: length
		))
		let maximumY = max(
			0,
			output.frame.height - scroll.contentSize.height
		)
		let maximumX = max(
			0,
			output.frame.width - scroll.contentSize.width
		)
		let origin = NSPoint(
			x: min(
				maximumX,
				max(
					0,
					position.origin.x
				)
			),
			y: min(
				maximumY,
				max(
					0,
					position.origin.y
				)
			)
		)
		scroll.contentView.scroll(to: origin)
		scroll.reflectScrolledClipView(scroll.contentView)
		pendingOutputReadingPosition = nil
	}

	private func updateOutputDocumentSize()
	{
		guard scroll.contentSize.width > 0,
				let container = output.textContainer, let manager = output.layoutManager
		else
		{
			return
		}
		manager.ensureLayout(for: container)
		let textRect = manager.usedRect(for: container)
		output.setFrameSize(NSSize(
			width: max(
				scroll.contentSize.width,
				ceil(textRect.maxX) + 28
			),
			height: max(
				scroll.contentSize.height,
				ceil(textRect.height) + output.textContainerInset.height * 2
			)
		))
		scroll.updateEdgeFades()
	}

	private static func commandText(_ command: String) -> NSAttributedString
	{
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byWordWrapping
		paragraph.lineSpacing = terminalLineSpacing
		return NSAttributedString(
			string: "$ \(command)",
			attributes: [
				.font: terminalFont,
				.foregroundColor: AppKitColorTokens.terminalText,
				.paragraphStyle: paragraph
			]
		)
	}

	private static func commandHeight(
		_ command: String,
		width: CGFloat
	) -> CGFloat
	{
		// Match the two-line preview and keep its 24pt copy target inside the command area.
		let text = commandText(String(command.prefix(maximumShellSampleLength)))
		let measured = text.boundingRect(
			with: NSSize(
				width: max(
					1,
					width - DesktopOutputCard.contentInset * 2 - 28
				),
				height: .greatestFiniteMagnitude
			),
			options: [.usesLineFragmentOrigin, .usesFontLeading]
		).height
		return max(
			24,
			min(
				ceil(measured),
				terminalLineHeight * 2 - terminalLineSpacing
			)
		)
	}

	static func height(
		command: ConversationCommand,
		width: CGFloat
	) -> CGFloat
	{
		// Unwrapped lines determine height independently of the transcript width.
		return shellHeight(
			command: command,
			previewHeight: commandHeight(
				command.command,
				width: width
			)
		)
	}

	static func sampledShellLineCount(_ output: String) -> Int
	{
		var lineCount = 1
		var sampledCharacters = 0
		for character in output
		{
			guard sampledCharacters < maximumShellSampleLength, lineCount < 20
			else
			{
				break
			}
			sampledCharacters += 1
			if character == "\n" || character == "\r\n"
			{
				lineCount += 1
			}
		}
		return lineCount
	}

	private static func shellHeight(
		command: ConversationCommand,
		previewHeight: CGFloat
	) -> CGFloat
	{
		let lineCount = sampledShellLineCount(command.output)
		let outputHeight = max(
			24,
			ceil(CGFloat(min(
				lineCount,
				20
			)) * terminalLineHeight) + 6
		)
		return min(
			maximumShellHeight,
			max(
				minimumShellHeight,
				previewHeight + outputHeight + DesktopOutputCard.headerAndInsetsHeight + 31
			)
		)
	}

	private static func shellStatus(_ command: ConversationCommand) -> String
	{
		ConversationCommandOutcome(command).detailTitle
	}

	private static func metadata(_ command: ConversationCommand) -> String
	{
		var parts = [command.status]
		if let cwd = command.cwd
		{
			parts.append(cwd)
		}
		if let exitCode = command.exitCode
		{
			parts.append("Exit \(exitCode)")
		}
		if let milliseconds = command.durationMs
		{
			parts.append(String(
				format: "%.1fs",
				max(
					0,
					milliseconds
				) / 1000
			))
		}
		return parts.joined(separator: " · ")
	}

}

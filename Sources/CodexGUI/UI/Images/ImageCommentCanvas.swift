import AppKit

/// Owns image-local comment editing while keeping markers at control size through zoom.
@MainActor
final class ImageCommentCanvas: NSView
{
	private(set) var annotations: [ImageAnnotation]
	private(set) var isCommenting = false
	var onChange: (() -> Void)?
	weak var imageScrollView: NSScrollView?
	var imageRect = NSRect.zero
	{
		didSet
		{
			needsLayout = true
		}
	}
	private var originalAnnotations: [ImageAnnotation]
	private var pins: [DesktopActionButton] = []
	private var editor: ImageCommentEditor?
	private var editingAnnotation: ImageAnnotation?
	private var isNewComment = false

	init(annotations: [ImageAnnotation])
	{
		self.annotations = annotations.filter(\.isValid)
		originalAnnotations = self.annotations
		super.init(frame: .zero)
		setAccessibilityElement(true)
		setAccessibilityRole(.group)
		setAccessibilityLabel("Image comments")
		rebuildPins()
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func beginCommenting()
	{
		originalAnnotations = annotations
		isCommenting = true
		window?.makeFirstResponder(self)
		rebuildPins()
		onChange?()
	}

	func cancelCommenting()
	{
		closeEditor()
		annotations = originalAnnotations
		isCommenting = false
		rebuildPins()
		onChange?()
	}

	@discardableResult
	func commitEditing() -> Bool
	{
		guard let editor
		else
		{
			return true
		}
		return editor.save()
	}

	@discardableResult
	func cancelEditing() -> Bool
	{
		guard editor != nil
		else
		{
			return false
		}
		closeEditor()
		return true
	}

	override func hitTest(_ point: NSPoint) -> NSView?
	{
		let local = convert(
			point,
			from: superview
		)
		guard bounds.contains(local)
		else
		{
			return nil
		}
		let target = super.hitTest(point)
		if target !== self
		{
			return target
		}
		return isCommenting && imageRect.contains(local) ? self : nil
	}

	override var acceptsFirstResponder: Bool
	{
		isCommenting
	}

	override func keyDown(with event: NSEvent)
	{
		if [36, 76, 49].contains(event.keyCode)
		{
			let visible = imageRect.intersection(bounds)
			guard !visible.isEmpty
			else
			{
				return
			}
			addComment(at: NSPoint(
				x: visible.midX,
				y: visible.midY
			))
		}
		else
		{
			super.keyDown(with: event)
		}
	}

	override func scrollWheel(with event: NSEvent)
	{
		imageScrollView?.scrollWheel(with: event)
	}

	override func magnify(with event: NSEvent)
	{
		imageScrollView?.magnify(with: event)
	}

	override func mouseDown(with event: NSEvent)
	{
		addComment(at: convert(
			event.locationInWindow,
			from: nil
		))
	}

	func addComment(at point: NSPoint)
	{
		guard isCommenting, imageRect.width > 0, imageRect.height > 0,
				imageRect.contains(point), commitEditing()
		else
		{
			return
		}
		let annotation = ImageAnnotation(
			x: Double((point.x - imageRect.minX) / imageRect.width),
			y: Double((imageRect.maxY - point.y) / imageRect.height),
			text: ""
		)
		openEditor(
			annotation,
			isNew: true
		)
	}

	private func openEditor(
		_ annotation: ImageAnnotation,
		isNew: Bool
	)
	{
		closeEditor()
		editingAnnotation = annotation
		isNewComment = isNew
		let editor = ImageCommentEditor(
			text: annotation.text,
			existing: !isNew
		)
		self.editor = editor
		editor.onSave =
		{
			[weak self] text in
			guard let self, var annotation = self.editingAnnotation
			else
			{
				return
			}
			annotation.text = text
			if let index = self.annotations.firstIndex(where:
				{
					$0.id == annotation.id
				})
			{
				self.annotations[index] = annotation
			}
			else
			{
				self.annotations.append(annotation)
			}
			self.closeEditor()
			self.focusPin(id: annotation.id)
			self.onChange?()
		}
		editor.onCancel =
		{
			[weak self] in self?.closeEditor()
		}
		editor.onDelete =
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			self.annotations.removeAll
			{
				$0.id == annotation.id
			}
			self.closeEditor()
			self.window?.makeFirstResponder(self)
			self.onChange?()
		}
		addSubview(editor)
		rebuildPins()
		layoutSubtreeIfNeeded()
		window?.makeFirstResponder(editor.focusView)
	}

	private func closeEditor()
	{
		if let editor, (window?.firstResponder as? NSView)?.isDescendant(of: editor) == true
			|| editor.inputField?.currentEditor() === window?.firstResponder
		{
			window?.makeFirstResponder(self)
		}
		editor?.removeFromSuperview()
		editor = nil
		editingAnnotation = nil
		isNewComment = false
		rebuildPins()
	}

	private func rebuildPins()
	{
		pins.forEach
		{
			$0.removeFromSuperview()
		}
		pins = []
		var displayed = annotations
		if isNewComment, let editingAnnotation
		{
			displayed.append(editingAnnotation)
		}
		for (index, annotation) in displayed.enumerated()
		{
			let button = DesktopActionButton(
				title: String(index + 1),
				presentation: .annotationPin
			)
			button.keyboardFocusPolicy = .dialog
			button.setAccessibilityLabel("Edit comment \(index + 1)")
			button.setAccessibilityIdentifier("image-comment-\(annotation.id)")
			button.onAction =
			{
				[weak self] in
				guard let self, self.commitEditing()
				else
				{
					return
				}
				self.isCommenting = true
				let current = self.annotations
					.first(where:
						{
							$0.id == annotation.id
						}) ?? annotation
				self.openEditor(
					current,
					isNew: false
				)
				self.onChange?()
			}
			pins.append(button)
			addSubview(
				button,
				positioned: .below,
				relativeTo: editor
			)
		}
		needsLayout = true
	}

	override func layout()
	{
		super.layout()
		var displayed = annotations
		if isNewComment, let editingAnnotation
		{
			displayed.append(editingAnnotation)
		}
		for (pin, annotation) in zip(
			pins,
			displayed
		)
		{
			let center = position(of: annotation)
			pin.frame = NSRect(
				x: center.x - 15,
				y: center.y - 15,
				width: 30,
				height: 30
			)
			pin.isHidden = !imageRect.intersects(pin.frame) || !bounds.intersects(pin.frame)
		}
		if let editor, let editingAnnotation
		{
			let center = position(of: editingAnnotation)
			let width = min(
				294,
				max(
					0,
					bounds.width - 16
				)
			)
			let height = min(
				editor.preferredHeight,
				max(
					0,
					bounds.height - 16
				)
			)
			let right = center.x + 27
			let x = right + width <= bounds.maxX - 8 ? right : center.x - 27 - width
			editor.frame = NSRect(
				x: min(
					max(
						8,
						x
					),
					max(
						8,
						bounds.width - width - 8
					)
				),
				y: min(
					max(
						8,
						center.y - height / 2
					),
					max(
						8,
						bounds.height - height - 8
					)
				),
				width: width,
				height: height
			)
		}
	}

	private func focusPin(id: String)
	{
		layoutSubtreeIfNeeded()
		if let pin = pins.first(where:
			{
				$0.accessibilityIdentifier() == "image-comment-\(id)"
			})
		{
			window?.makeFirstResponder(pin)
		}
	}

	private func position(of annotation: ImageAnnotation) -> NSPoint
	{
		NSPoint(
			x: imageRect.minX + CGFloat(annotation.x) * imageRect.width,
			y: imageRect.maxY - CGFloat(annotation.y) * imageRect.height
		)
	}
}

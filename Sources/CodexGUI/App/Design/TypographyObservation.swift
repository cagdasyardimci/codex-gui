import AppKit
import ObjectiveC

/// An owner-retained, weak-capturing subscription for prepared text and layout refresh.
@MainActor
final class TypographyObservation: NSObject
{
	private let update: @MainActor () -> Void
	private weak var observedView: NSView?
	private let includesColorChanges: Bool
	private var appearanceObservation: NSKeyValueObservation?

	init(
		center: NotificationCenter = .default,
		view: NSView? = nil,
		includesColorChanges: Bool = true,
		update: @escaping @MainActor () -> Void
	)
	{
		self.update = update
		self.includesColorChanges = includesColorChanges
		self.observedView = view
		super.init()
		center.addObserver(
			self,
			selector: #selector(changed(_:)),
			name: TypographyPreferences.didChange,
			object: nil
		)
		if let view
		{
			appearanceObservation = view.observe(
				\.effectiveAppearance,
				options: [.old, .new]
			)
			{
				[weak self] _, change in
				guard change.oldValue?.name != change.newValue?.name
				else
				{
					return
				}
				Task
				{
					@MainActor [weak self] in
					self?.update()
				}
			}
		}
		center.addObserver(
			self,
			selector: #selector(changed(_:)),
			name: ColorPreferences.didChange,
			object: nil
		)
	}

	@objc private func changed(_ notification: Notification)
	{
		if !includesColorChanges, notification.name == ColorPreferences.didChange,
			notification.userInfo?[ColorPreferences.typographyChangedKey] as? Bool == false
		{
			// Dynamic text colors still need painting, without font replacement or layout work.
			observedView?.needsDisplay = true
			return
		}
		update()
	}
}

@MainActor private var typographyBindingKey: UInt8 = 0

@MainActor
extension NSControl
{
	func setTypographyRole(
		_ role: TypographyTokens.Role,
		italic: Bool = false,
		configuration: @escaping @MainActor () -> TypographyConfiguration =
		{
			.current
		},
		center: NotificationCenter = .default,
		onUpdate: @escaping @MainActor () -> Void =
		{
		}
	)
	{
		let apply: @MainActor () -> Void =
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			let imagePosition = (self as? NSButton)?.imagePosition
			let config = configuration()
			self.font = AppKitFontResolver.font(
				role,
				italic: italic,
				configuration: config,
				appearance: self.effectiveAppearance
			)
			let retained: NSAttributedString?
			if let button = self as? NSButton,
				!(button is NSPopUpButton)
			{
				retained = (button as? DesktopAttributedTitleButton)?
					.semanticAttributedTitle ?? button.attributedTitle
			}
			else if let field = self as? NSTextField
			{
				retained = field.attributedStringValue
			}
			else
			{
				retained = nil
			}
			if let retained, retained.length > 0
			{
				let text = NSMutableAttributedString(attributedString: retained)
				let attributes = AppKitFontResolver.textAttributes(
					role,
					font: self.font,
					configuration: config,
					alignment: self.alignment,
					lineBreakMode: self.cell?.lineBreakMode
				)
				text.addAttributes(
					attributes,
					range: NSRange(
						location: 0,
						length: text.length
					)
				)
				if let button = self as? NSButton
				{
					button.attributedTitle = text
				}
				else if let field = self as? NSTextField
				{
					field.attributedStringValue = text
				}
			}
			// AppKit can switch to image-overlapping text when replacing an attributed title.
			if let button = self as? NSButton, let imagePosition,
				button.imagePosition != imagePosition
			{
				button.imagePosition = imagePosition
			}
			self.invalidateIntrinsicContentSize()
			self.needsLayout = true
			self.needsDisplay = true
			self.superview?.needsLayout = true
			onUpdate()
		}
		let observation = TypographyObservation(
			center: center,
			view: self,
			includesColorChanges: false,
			update: apply
		)
		objc_setAssociatedObject(
			self,
			&typographyBindingKey,
			observation,
			.OBJC_ASSOCIATION_RETAIN_NONATOMIC
		)
		apply()
	}
}

@MainActor
extension NSTextView
{
	func setTypographyRole(
		_ role: TypographyTokens.Role,
		configuration: @escaping @MainActor () -> TypographyConfiguration =
		{
			.current
		},
		center: NotificationCenter = .default
	)
	{
		let apply: @MainActor () -> Void =
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			let selection = self.selectedRanges
			let config = configuration()
			let font = AppKitFontResolver.font(
				role,
				configuration: config,
				appearance: self.effectiveAppearance
			)
			let attributes = AppKitFontResolver.textAttributes(
				role,
				font: font,
				configuration: config
			)
			self.font = font
			if let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle
			{
				self.defaultParagraphStyle = paragraph
			}
			self.typingAttributes.merge(attributes)
			{
				_, value in value
			}
			if let storage = self.textStorage, storage.length > 0
			{
				storage.addAttributes(
					attributes,
					range: NSRange(
						location: 0,
						length: storage.length
					)
				)
			}
			self.selectedRanges = selection
			self.invalidateIntrinsicContentSize()
			self.needsLayout = true
			self.needsDisplay = true
			self.enclosingScrollView?.needsLayout = true
		}
		let observation = TypographyObservation(
			center: center,
			view: self,
			includesColorChanges: false,
			update: apply
		)
		objc_setAssociatedObject(
			self,
			&typographyBindingKey,
			observation,
			.OBJC_ASSOCIATION_RETAIN_NONATOMIC
		)
		apply()
	}
}

@MainActor
extension NSMenu
{
	func setTypographyRole(_ role: TypographyTokens.Role)
	{
		let apply: @MainActor () -> Void =
		{
			[weak self] in
			self?.font = AppKitFontResolver.font(role)
		}
		objc_setAssociatedObject(
			self,
			&typographyBindingKey,
			TypographyObservation(
				includesColorChanges: false,
				update: apply
			),
			.OBJC_ASSOCIATION_RETAIN_NONATOMIC
		)
		apply()
	}
}

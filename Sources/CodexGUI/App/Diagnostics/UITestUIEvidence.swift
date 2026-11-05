import AppKit
import CoreText

/// Bounded opt-in snapshots of retained AppKit presentation; contains no user text.
@MainActor
final class UITestUIEvidence
{
	static let shared = UITestUIEvidence()
	private let recorder: UITestEvidenceRecorder
	private var pending: Task<Void, Never>?
	private var viewers: [ObjectIdentifier: WeakViewer] = [:]
	private var sequence = 0

	init(recorder: UITestEvidenceRecorder = .shared)
	{
		self.recorder = recorder
	}

	func install()
	{
		guard recorder.isEnabled
		else
		{
			return
		}
		recorder.uiCaptureRequested =
		{
			[weak self] in self?.request()
		}
		recorder.uiViewerChanged =
		{
			[weak self] object, active in
			guard let viewer = object as? ExpandedImageViewController
			else
			{
				return
			}
			self?.viewerChanged(
				viewer,
				active: active
			)
		}
		request()
	}

	func request()
	{
		guard recorder.isEnabled, pending == nil
		else
		{
			return
		}
		pending = Task
		{
			@MainActor [weak self] in
			try? await Task.sleep(for: .milliseconds(150))
			guard let self
			else
			{
				return
			}
			self.pending = nil
			self.capture()
		}
	}

	func viewerChanged(
		_ viewer: ExpandedImageViewController,
		active: Bool = true
	)
	{
		guard recorder.isEnabled
		else
		{
			return
		}
		let key = ObjectIdentifier(viewer)
		if active
		{
			viewers[key] = WeakViewer(viewer)
		}
		else
		{
			viewers.removeValue(forKey: key)
		}
		request()
	}

	func capture()
	{
		guard recorder.isEnabled
		else
		{
			return
		}
		sequence += 1
		var remaining = 500
		let viewerWindows = Set(viewers.values.compactMap
		{
			$0.value?.view.window
		}
		.map(ObjectIdentifier.init))
		let windows = NSApp.windows.filter(\.isVisible).sorted
		{
			viewerWindows.contains(ObjectIdentifier($0)) && !viewerWindows
				.contains(ObjectIdentifier($1))
		}.map
		{
			window -> [String: Any] in
			var views: [[String: Any]] = []
			if let content = window.contentView
			{
				collect(
					content,
					into: &views,
					remaining: &remaining
				)
			}
			return ["identity": identity(window),
					"number": window.windowNumber,
					"appearance": window.effectiveAppearance.name.rawValue,
					"frame": rect(window.frame),
					"views": views,
					"semanticColors": [
						"primaryText": rgba(
							AppKitColorTokens.primaryText,
							appearance: window.effectiveAppearance
						) ?? [],
						"imageControlSurface": rgba(
							AppKitColorTokens.imageControlSurface,
							appearance: window.effectiveAppearance
						) ?? [],
						"imageControlHover": rgba(
							AppKitColorTokens.imageControlHover,
							appearance: window.effectiveAppearance
						) ?? [],
						"imageControlText": rgba(
							AppKitColorTokens.imageControlText,
							appearance: window.effectiveAppearance
						) ?? []
					]]
		}
		viewers = viewers.filter
		{
			$0.value.value != nil
		}
		let expanded = viewers.values.compactMap(\.value).map
		{
			viewer -> [String: Any] in
			let clip = viewer.scrollView.contentView.bounds
			var controls: [[String: Any]] = []
			var controlBudget = 128
			collect(
				viewer.view,
				into: &controls,
				remaining: &controlBudget
			)
			return [
				"views": controls,
				"controller": identity(viewer),
				"view": identity(viewer.view),
				"window": viewer.view.window.map(identity) ?? "",
				"zoom": viewer.scrollView.magnification,
				"scroll": rect(clip),
				"artwork": viewer.imageView.image.map(identity) ?? "",
				"artworkSize": [
					viewer.imageView.image?.size.width ?? 0,
					viewer.imageView.image?.size.height ?? 0
				],
				"appearance": viewer.scrollView.effectiveAppearance.name.rawValue
			]
		}

		let value: [String: Any] = ["schemaVersion": 1,
									"sequence": sequence,
									"time": Date().timeIntervalSince1970,
									"uptime": ProcessInfo.processInfo.systemUptime,
									"windows": windows,
									"expandedViewers": expanded,
									"truncated": remaining == 0]
		if let data = try? JSONSerialization.data(
			withJSONObject: value,
			options: [.sortedKeys]
		)
		{
			recorder.recordUI(data)
		}
	}

	private func collect(
		_ view: NSView,
		into output: inout [[String: Any]],
		remaining: inout Int
	)
	{
		guard remaining > 0
		else
		{
			return
		}
		remaining -= 1
		var item: [String: Any] = [
			"identity": identity(view),
			"class": String(describing: type(of: view)),
			"appearance": view.effectiveAppearance.name.rawValue,
			"frame": rect(view.frame),
			"hidden": view.isHidden,
			"alpha": view.alphaValue
		]
		let id = view.accessibilityIdentifier()
		if [
			"expanded-image-preview",
			"expanded-image-zoom",
			"expanded-image-close",
			"expanded-image-download",
			"expanded-diagram-canvas",
			"conversation-composer"
		].contains(id)
		{
			item["identifier"] = id
		}
		if let control = view as? NSControl,
			let font = control.font
		{
			item["font"] = fontInfo(font)
		}
		if let text = view as? NSTextView, let font = text.font
		{
			item["font"] = fontInfo(font)
		}
		if let button = view as? NSButton, button.attributedTitle.length > 0,
			let font = button.attributedTitle.attribute(
			.font,
			at: 0,
			effectiveRange: nil
			) as? NSFont
		{
			item["attributedFont"] = fontInfo(font)
		}
		if let color = (view as? NSTextField)?.textColor ?? (view as? NSTextView)?.textColor,
			let value = rgba(
			color,
			appearance: view.effectiveAppearance
			)
		{
			item["textColor"] = value
		}
		if let cg = view.layer?.backgroundColor, let color = NSColor(cgColor: cg),
			let value = rgba(
			color,
			appearance: view.effectiveAppearance
			)
		{
			item["layerBackground"] = value
		}
		output.append(item)
		for child in view.subviews
		{
			collect(
				child,
				into: &output,
				remaining: &remaining
			)
		}
	}

	private func fontInfo(_ font: NSFont) -> [String: Any]
	{
		var result: [String: Any] = [
			"name": font.fontName,
			"family": font.familyName ?? "",
			"size": font.pointSize
		]
		if let axes = CTFontCopyVariation(font as CTFont) as? [NSNumber: NSNumber]
		{
			result["variation"] = Dictionary(uniqueKeysWithValues: axes.map
			{
				(
					String($0.key.uint32Value),
					$0.value
				)
			})
		}
		return result
	}

	private func rgba(
		_ color: NSColor,
		appearance: NSAppearance
	) -> [CGFloat]?
	{
		var result: [CGFloat]?
		appearance.performAsCurrentDrawingAppearance
		{
			if let c = color.usingColorSpace(.sRGB)
			{
				result = [
					c.redComponent,
					c.greenComponent,
					c.blueComponent,
					c.alphaComponent
				]
			}
		}
		return result
	}

	private func rect(_ rect: NSRect) -> [CGFloat]
	{
		[
			rect.origin.x,
			rect.origin.y,
			rect.width,
			rect.height
		]
	}
	private func identity(_ object: AnyObject)
		-> String
	{
		String(describing: Unmanaged.passUnretained(object).toOpaque())
	}
	private final class WeakViewer
	{
		weak var value: ExpandedImageViewController?
		init(_ value: ExpandedImageViewController)
		{
			self.value = value
		}
	}
}

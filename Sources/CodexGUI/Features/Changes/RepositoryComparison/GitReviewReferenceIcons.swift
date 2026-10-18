import AppKit

/// Review controls reuse packaged artwork and native paths for the supplied reference forms.
@MainActor
enum GitReviewReferenceIcons
{
	enum Kind: CaseIterable
	{
		case documentSearch, refresh, returnToBoundary, collapse, displayMode, expand, panel
		case unifiedDisplayMode
		case swiftFile, eye, openFile, code, ellipsis, search, filter, folders
		case chevronDown, chevronRight, chevronLeft, info
	}

	static func image(
		_ kind: Kind,
		size: CGFloat = 16,
		accessibilityDescription: String? = nil
	) -> NSImage
	{
		if let asset = packagedAsset(kind)
		{
			return DesktopIcons.image(
				asset,
				size: size,
				accessibilityDescription: accessibilityDescription
			)
		}
		if kind == .swiftFile
		{
			return WorkspaceFileIcon.swiftImage(
				size: size,
				accessibilityDescription: accessibilityDescription
			)
		}
		let image = NSImage(
			size: NSSize(
				width: size,
				height: size
			),
			flipped: true
		)
		{
			bounds in
			NSGraphicsContext.saveGraphicsState()
			let transform = AffineTransform(scale: bounds.width / 24)
			(transform as NSAffineTransform).concat()
			draw(kind)
			NSGraphicsContext.restoreGraphicsState()
			return true
		}
		image.isTemplate = kind != .displayMode && kind != .unifiedDisplayMode
		image.accessibilityDescription = accessibilityDescription
		return image
	}

	static func fileImage(
		relativePath: String,
		isDirectory: Bool = false,
		isSymbolicLink: Bool = false,
		size: CGFloat = 16
	) -> NSImage
	{
		WorkspaceFileIcon.image(
			relativePath: relativePath,
			isDirectory: isDirectory,
			isSymbolicLink: isSymbolicLink,
			size: size
		)
	}

	static func fileImage(
		for type: WorkspaceFileTypePresentation,
		relativePath: String? = nil,
		size: CGFloat = 16
	) -> NSImage
	{
		WorkspaceFileIcon.image(
			for: type,
			relativePath: relativePath,
			size: size
		)
	}

	private static func packagedAsset(_ kind: Kind) -> DesktopIcon?
	{
		switch kind
		{
		case .refresh: .regenerate
		case .expand: .expand
		case .eye: .eye
		case .openFile: .linkExternalWebsite
		case .code: .code
		case .ellipsis: .dotsHorizontal
		case .search: .search
		case .filter: .filter
		case .folders: .folders
		case .chevronDown: .chevronSmallDown
		case .chevronRight: .chevronSmallRight
		case .chevronLeft: .chevronSmallLeft
		case .info: .info
		default: nil
		}
	}

	private static func draw(_ kind: Kind)
	{
		NSColor.black.setStroke()
		NSColor.black.setFill()
		switch kind
		{
		case .documentSearch:
			let page = NSBezierPath()
			page.move(to: point((10, 21)))
			page.line(to: point((5, 21)))
			page.curve(
				to: point((3, 19)),
				controlPoint1: point((3.5, 21)),
				controlPoint2: point((3, 20.5))
			)
			page.line(to: point((3, 5)))
			page.curve(
				to: point((5, 3)),
				controlPoint1: point((3, 3.5)),
				controlPoint2: point((3.5, 3))
			)
			page.line(to: point((14, 3)))
			page.line(to: point((19, 8)))
			page.line(to: point((19, 10)))
			stroke(page)
			line([(13, 3), (13, 8), (19, 8)])
			stroke(NSBezierPath(ovalIn: rect((12, 13, 7, 7))))
			line([(18, 19), (21, 22)])
		case .collapse:
			line([(12, 3), (12, 10)])
			line([(9, 7), (12, 10), (15, 7)])
			line([(12, 21), (12, 14)])
			line([(9, 17), (12, 14), (15, 17)])
			line([(17, 10), (22, 10)])
			line([(17, 14), (22, 14)])
		case .returnToBoundary:
			line([(21, 3), (21, 21)])
			let arrow = NSBezierPath()
			arrow.move(to: point((4, 7)))
			arrow.line(to: point((12, 7)))
			arrow.curve(
				to: point((16, 11)),
				controlPoint1: point((15, 7)),
				controlPoint2: point((16, 8))
			)
			arrow.line(to: point((16, 12)))
			arrow.curve(
				to: point((12, 16)),
				controlPoint1: point((16, 15)),
				controlPoint2: point((15, 16))
			)
			arrow.line(to: point((4, 16)))
			stroke(arrow)
			line([(8, 12), (4, 16), (8, 20)])
		case .panel:
			stroke(NSBezierPath(
				roundedRect: rect((3, 3, 18, 18)),
				xRadius: 2,
				yRadius: 2
			))
			line([(12, 3), (12, 21)])
		case .displayMode, .unifiedDisplayMode:
			let frame = NSBezierPath(
				roundedRect: rect((3, 3, 18, 18)),
				xRadius: 2,
				yRadius: 2
			)
			NSColor(
				calibratedWhite: 0.58,
				alpha: 1
			).setStroke()
			stroke(frame)
			NSColor(
				calibratedRed: 0.65,
				green: 0.22,
				blue: 0.24,
				alpha: 1
			).setFill()
			if kind == .unifiedDisplayMode
			{
				rect((6, 6, 12, 5)).fill()
			}
			else
			{
				triangle([(6, 6), (18, 6), (6, 18)]).fill()
			}
			NSColor(
				calibratedRed: 0.18,
				green: 0.48,
				blue: 0.28,
				alpha: 1
			).setFill()
			if kind == .unifiedDisplayMode
			{
				rect((6, 13, 12, 5)).fill()
			}
			else
			{
				triangle([(18, 6), (18, 18), (6, 18)]).fill()
			}
		default:
			break
		}
	}

	private static func point(_ values: (CGFloat, CGFloat)) -> NSPoint
	{
		NSPoint(
			x: values.0,
			y: values.1
		)
	}

	private static func rect(_ values: (CGFloat, CGFloat, CGFloat, CGFloat)) -> NSRect
	{
		NSRect(
			x: values.0,
			y: values.1,
			width: values.2,
			height: values.3
		)
	}

	private static func line(_ vertices: [(CGFloat, CGFloat)])
	{
		let path = triangle(vertices)
		stroke(path)
	}

	private static func triangle(_ vertices: [(CGFloat, CGFloat)]) -> NSBezierPath
	{
		let path = NSBezierPath()
		for (index, vertex) in vertices.enumerated()
		{
			if index == 0
			{
				path.move(to: point(vertex))
			}
			else
			{
				path.line(to: point(vertex))
			}
		}
		return path
	}

	private static func stroke(_ path: NSBezierPath)
	{
		path.lineWidth = 1.8
		path.lineCapStyle = .round
		path.lineJoinStyle = .round
		path.stroke()
	}
}

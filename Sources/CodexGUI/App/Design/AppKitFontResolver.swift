import AppKit
import CoreText

/// Converts typography roles into native fonts and font-related attributes.
@MainActor
enum AppKitFontResolver
{
	enum FontScope
	{
		case ui, content
	}

	static var availableFontFamilies: [String]
	{
		NSFontManager.shared.availableFontFamilies
			.filter
			{
				!$0.hasPrefix(".")
			}
			.sorted
			{
				$0.localizedStandardCompare($1) == .orderedAscending
			}
	}
	private static let interfaceFonts: NSCache<NSString, NSFont> =
	{
		let cache = NSCache<NSString, NSFont>()
		cache.countLimit = 128
		return cache
	}()
	private static let familyFonts: NSCache<NSString, NSFont> =
	{
		let cache = NSCache<NSString, NSFont>()
		cache.countLimit = 128
		return cache
	}()

	static func interfaceFont(
		ofSize size: CGFloat,
		weight: TypographyTokens.Weight = .text,
		italic: Bool = false
	) -> NSFont
	{
		let key = "\(size):\(weight.rawValue):\(italic)" as NSString
		if let font = interfaceFonts.object(forKey: key)
		{
			return font
		}

		// Rendered Fonts reports SF NS with exact wght values and minimum opsz 17.
		let opticalSize = max(
			TypographyTokens.opticalSizeMinimum,
			size
		)
		var variations: [NSNumber: NSNumber] = [
			NSNumber(value: 0x77676874): NSNumber(value: Double(weight.rawValue)), // wght
			NSNumber(value: 0x6F70737A): NSNumber(value: Double(opticalSize)), // opsz
		]
		// The measured SF bold-italic instance retains the text companion axis.
		if italic && weight == .strong
		{
			variations[NSNumber(value: 0x59415853)] = 430 // YAXS
		}

		let descriptor = CTFontDescriptorCreateWithAttributes([
			kCTFontVariationAttribute: variations,
		] as CFDictionary)
		let uprightSystemFont = NSFont.systemFont(ofSize: size)
		// Select the native italic face before resolving graphics and exact variation axes.
		// Converting the graphics-derived face requests a private name and triggers fallback.
		let systemFont = italic
			? NSFont(
				descriptor: uprightSystemFont.fontDescriptor.withSymbolicTraits(.italic),
				size: size
			) ?? uprightSystemFont : uprightSystemFont
		// Resolve its graphics font first; a system UI descriptor ignores explicit variations.
		let graphicsFont = CTFontCopyGraphicsFont(
			systemFont as CTFont,
			nil
		)
		let font = CTFontCreateWithGraphicsFont(
			graphicsFont,
			size,
			nil,
			descriptor
		) as NSFont
		interfaceFonts.setObject(
			font,
			forKey: key
		)
		return font
	}

	static func font(
		_ role: TypographyTokens.Role,
		italic: Bool = false,
		configuration: TypographyConfiguration = .current,
		appearance: NSAppearance? = nil,
		colorConfiguration: ColorThemeConfiguration = ColorPreferences().configuration,
		scope: FontScope = .ui
	) -> NSFont
	{
		let resolved = role.resolved(using: configuration)
		let actualAppearance = appearance ?? NSApp?.effectiveAppearance ?? NSAppearance.current
		let mode: ColorAppearance
		switch colorConfiguration.mode
		{
		case .dark: mode = .dark
		case .light: mode = .light
		case .system: mode = actualAppearance?
			.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
		}
		let profile = colorConfiguration.profile(for: mode)
		let preset = profile.presetID.flatMap
		{
			ColorThemePresets.preset(
				id: $0,
				appearance: mode
			)
		}
		let presetFamily: String?
		switch role.selection
		{
		case .code: presetFamily = profile.codeFontFamily ?? preset?.codeFontFamily
		case .interface: presetFamily = scope == .content ?
			(profile.contentFontFamily ?? profile.uiFontFamily ?? preset?.contentFontFamily
				?? preset?.uiFontFamily)
			: (profile.uiFontFamily ?? preset?.uiFontFamily)
		default: presetFamily = nil
		}
		if let list = presetFamily, let family = firstAvailableFamily(in: list)
		{
			return familyFont(
				family,
				size: resolved.size,
				weight: role.weight,
				italic: italic
			)
		}
		// Named/code faces own italic selection; never convert a resolved regular face to bold.
		switch role.selection
		{
		case let .family(
			name,
			weight
		):
			return familyFont(
				name,
				size: resolved.size,
				weight: weight,
				italic: italic
			)
		case let .code(weight):
			return familyFont(
				"Menlo",
				size: resolved.size,
				weight: weight,
				italic: italic
			)
		default: break
		}

		if italic
		{
			if case let .interface(weight) = role.selection
			{
				return interfaceFont(
					ofSize: resolved.size,
					weight: weight,
					italic: true
				)
			}
			return NSFontManager.shared.convert(
				font(
					role,
					configuration: configuration
				),
				toHaveTrait: .italicFontMask
			)
		}

		func nativeWeight(_ weight: TypographyTokens.NativeWeight) -> NSFont.Weight
		{
			switch weight
			{
			case .regular: .regular
			case .medium: .medium
			case .semibold: .semibold
			case .bold: .bold
			}
		}
		switch role.selection
		{
		case .nativeButton:
			let native = NSButton(
				title: "",
				target: nil,
				action: nil
			).font ?? NSFont
				.systemFont(ofSize: 13)
			return native.pointSize == resolved.size ? native : NSFontManager.shared.convert(
				native,
				toSize: resolved.size
			)
		case let .interface(weight):
			return interfaceFont(
				ofSize: resolved.size,
				weight: weight
			)
		case let .system(weight):
			return .systemFont(
				ofSize: resolved.size,
				weight: nativeWeight(weight)
			)
		case .code, .family:
			preconditionFailure("Named fonts are resolved before native selections")
		}
	}

	static func firstAvailableFamily(in list: String) -> String?
	{
		for component in list.split(separator: ",")
		{
			let name = component.trimmingCharacters(in: .whitespacesAndNewlines)
				.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
			switch name.lowercased()
			{
			case "ui-monospace", "monospace": return "Menlo"
			case "ui-sans-serif", "sans-serif", "system-ui", "-apple-system": return nil
			default: break
			}
			if !(NSFontManager.shared.availableMembers(ofFontFamily: name) ?? [])
				.isEmpty
			{
				return name
			}
			if NSFont(
				name: name,
				size: 12
			) != nil
			{
				return name
			}
		}
		return nil
	}

	/// Select an installed face using CSS's special 400...500 search order.
	/// Missing italic faces retain the family; bold is never synthesized.
	static func familyFont(
		_ family: String,
		size: CGFloat,
		weight: TypographyTokens.Weight,
		italic: Bool = false
	) -> NSFont
	{
		if family == "OpenAI Sans"
		{
			LocalTypographyFonts.registerOpenAISans()
		}
		let key = "\(family)|\(size)|\(weight.rawValue)|\(italic)" as NSString
		if let cached = familyFonts.object(forKey: key)
		{
			return cached
		}
		struct Face
		{
			let font: NSFont
			let weight: Int
			let italic: Bool
		}
		let faces = (NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []).compactMap
		{
			member -> Face? in
			guard let name = member.first as? String, let font = NSFont(
				name: name,
				size: size
			)
			else
			{
				return nil
			}
			// OpenType OS/2.usWeightClass is the CSS numeric weight, unlike AppKit's weight scale.
			let table = CTFontCopyTable(
				font as CTFont,
				CTFontTableTag(0x4F532F32),
				[]
			) as Data?
			let numeric = table.flatMap
			{
				$0.count >= 6 ? Int($0[4]) * 256 + Int($0[5]) : nil
			}
			let fallback = font.fontDescriptor.symbolicTraits.contains(.bold) ? 700 : 400
			return Face(
				font: font,
				weight: numeric ?? fallback,
				italic: font.fontDescriptor.symbolicTraits.contains(.italic)
			)
		}
		let styled = faces.filter
		{
			$0.italic == italic
		}
		let candidates = styled.isEmpty ? faces.filter
		{
			!$0.italic
		} : styled
		guard let selectedWeight = FontWeightMatching.match(
			weight.rawValue,
			available: candidates.map(\.weight)
		),
			let selected = candidates.first(where:
				{
					$0.weight == selectedWeight
				})
		else
		{
			if let direct = NSFont(
				name: family,
				size: size
			)
			{
				return italic ? (NSFont(
					descriptor: direct.fontDescriptor.withSymbolicTraits(.italic),
					size: size
				) ?? direct) : direct
			}
			return interfaceFont(
				ofSize: size,
				weight: weight,
				italic: italic
			)
		}
		familyFonts.setObject(
			selected.font,
			forKey: key
		)
		return selected.font
	}

	/// WebKit receives the resolved UI family and the diagram roles before measuring its layout.
	static func diagramTypography(
		appearance: NSAppearance,
		configuration: TypographyConfiguration = .current,
		colorConfiguration: ColorThemeConfiguration = ColorPreferences().configuration
	) -> [String: Any]
	{
		let body = TypographyTokens.Diagram.body
		let resolvedFont = font(
			body,
			configuration: configuration,
			appearance: appearance,
			colorConfiguration: colorConfiguration,
			scope: .ui
		)
		let family = resolvedFont.familyName ?? resolvedFont.fontName
		let cssFamily = resolvedFont.fontName.hasPrefix(".") ? "-apple-system" :
			"\"" + family.replacingOccurrences(
				of: "\\",
				with: "\\\\"
			)
			.replacingOccurrences(
				of: "\"",
				with: "\\\""
			) + "\""
		return [
			"fontFamily": cssFamily,
			"bodySize": body.resolved(using: configuration).size,
			"edgeSize": TypographyTokens.Diagram.edge.resolved(using: configuration).size,
			"nodeSize": TypographyTokens.Diagram.node.resolved(using: configuration).size,
			"bodyWeight": body.weight.rawValue,
			"edgeWeight": TypographyTokens.Diagram.edge.weight.rawValue,
			"nodeWeight": TypographyTokens.Diagram.node.weight.rawValue
		]
	}

	static func textAttributes(
		_ role: TypographyTokens.Role,
		font resolvedFont: NSFont? = nil,
		configuration: TypographyConfiguration = .current,
		alignment: NSTextAlignment? = nil,
		lineBreakMode: NSLineBreakMode? = nil
	) -> [NSAttributedString.Key: Any]
	{
		var attributes: [NSAttributedString.Key: Any] = [.font: resolvedFont ?? font(
			role,
			configuration: configuration
		)]
		if let tracking = role.tracking
		{
			attributes[.kern] = tracking
		}
		if let ligatures = role.ligatures
		{
			attributes[.ligature] = ligatures
		}
		let resolved = role.resolved(using: configuration)
		if resolved.lineHeight != nil || resolved.lineSpacing != nil || alignment != nil
			|| lineBreakMode != nil
		{
			let paragraph = NSMutableParagraphStyle()
			let native = resolvedFont ?? font(
				role,
				configuration: configuration
			)
			let fittedHeight: CGFloat
			if case .fixed = role.lineHeightRule
			{
				// Fixed control rows keep their line box; glyphs may extend into its padding.
				fittedHeight = resolved.lineHeight ?? 0
			}
			else
			{
				fittedHeight = max(
					resolved.lineHeight ?? 0,
					native.ascender - native.descender + native.leading
				)
			}
			if resolved.lineHeight != nil
			{
				paragraph.minimumLineHeight = fittedHeight
				paragraph.maximumLineHeight = fittedHeight
			}
			paragraph.lineSpacing = resolved.lineSpacing ?? 0
			if let alignment
			{
				paragraph.alignment = alignment
			}
			if let lineBreakMode
			{
				paragraph.lineBreakMode = lineBreakMode
			}
			attributes[.paragraphStyle] = paragraph
		}

		return attributes
	}

}

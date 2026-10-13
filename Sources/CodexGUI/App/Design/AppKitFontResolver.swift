import AppKit
import CoreText

/// Converts typography roles into native fonts and font-related attributes.
@MainActor
enum AppKitFontResolver
{
	static func interfaceFont(
		ofSize size: CGFloat,
		weight: CGFloat = TypographyTokens.interfaceWeight
	) -> NSFont
	{
		// Rendered Fonts reports SF NS with exact wght values and minimum opsz 17.
		let opticalSize = max(
			TypographyTokens.opticalSizeMinimum,
			size
		)
		let variations: [NSNumber: NSNumber] = [
			NSNumber(value: 0x77676874): NSNumber(value: Double(weight)), // wght
			NSNumber(value: 0x6F70737A): NSNumber(value: Double(opticalSize)), // opsz
		]
		let descriptor = CTFontDescriptorCreateWithAttributes([
			kCTFontVariationAttribute: variations,
		] as CFDictionary)
		let systemFont = NSFont.systemFont(ofSize: size)
		// Resolve its graphics font first; a system UI descriptor ignores explicit variations.
		let graphicsFont = CTFontCopyGraphicsFont(
			systemFont as CTFont,
			nil
		)
		return CTFontCreateWithGraphicsFont(
			graphicsFont,
			size,
			nil,
			descriptor
		) as NSFont
	}

	static func font(_ role: TypographyTokens.Role) -> NSFont
	{
		func nativeWeight(_ weight: TypographyTokens.Weight) -> NSFont.Weight
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
		case let .interface(weight):
			return interfaceFont(
				ofSize: role.size,
				weight: weight
			)
		case let .system(weight):
			return .systemFont(
				ofSize: role.size,
				weight: nativeWeight(weight)
			)
		case let .monospaced(weight):
			return .monospacedSystemFont(
				ofSize: role.size,
				weight: nativeWeight(weight)
			)
		case let .menlo(bold):
			return NSFont(
				name: bold ? "Menlo-Bold" : "Menlo-Regular",
				size: role.size
			)
				?? .monospacedSystemFont(
					ofSize: role.size,
					weight: bold ? .semibold : .regular
				)
		}
	}

	static func textAttributes(
		_ role: TypographyTokens.Role,
		font resolvedFont: NSFont? = nil
	) -> [NSAttributedString.Key: Any]
	{
		var attributes: [NSAttributedString.Key: Any] = [.font: resolvedFont ?? font(role)]
		if let tracking = role.tracking
		{
			attributes[.kern] = tracking
		}
		if let ligatures = role.ligatures
		{
			attributes[.ligature] = ligatures
		}
		return attributes
	}

}

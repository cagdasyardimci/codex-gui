import AppKit

/// Native color construction and resolution without knowledge of named roles.
@MainActor
enum AppKitColorResolution
{
	/// Source-over in sRGB, avoiding AppKit's generic-RGB interpolation for flattened web surfaces.
	static func composite(
		_ foreground: NSColor,
		over background: NSColor
	) -> NSColor
	{
		guard let front = foreground.usingColorSpace(.sRGB),
				let back = background.usingColorSpace(.sRGB)
		else
		{
			return background
		}
		let frontAlpha = front.alphaComponent
		let backAlpha = back.alphaComponent * (1 - frontAlpha)
		let alpha = frontAlpha + backAlpha
		guard alpha > 0
		else
		{
			return .clear
		}
		return NSColor(
			srgbRed: (front.redComponent * frontAlpha + back.redComponent * backAlpha) / alpha,
			green: (front.greenComponent * frontAlpha + back.greenComponent * backAlpha) / alpha,
			blue: (front.blueComponent * frontAlpha + back.blueComponent * backAlpha) / alpha,
			alpha: alpha
		)
	}

	static func adaptiveColor(_ provider: @escaping (NSAppearance) -> NSColor) -> NSColor
	{
		NSColor(
			name: nil,
			dynamicProvider: provider
		)
	}

	/// Layer colors must be resolved again whenever their owning view's appearance changes.
	static func resolvedCGColor(
		_ color: NSColor,
		for view: NSView,
		alpha: CGFloat? = nil
	) -> CGColor
	{
		var resolvedColor: CGColor!
		view.effectiveAppearance.performAsCurrentDrawingAppearance
		{
			if let alpha
			{
				resolvedColor = color.withAlphaComponent(alpha).cgColor
			}
			else
			{
				resolvedColor = color.cgColor
			}
		}
		return resolvedColor
	}

	static func color(
		light: UInt32,
		dark: UInt32,
		lightAlpha: CGFloat = 1,
		darkAlpha: CGFloat = 1
	) -> NSColor
	{
		NSColor(name: nil)
		{
			appearance in
			let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
			let rgbHexValue = isDark ? dark : light
			return NSColor(
				srgbRed: CGFloat((rgbHexValue >> 16) & 0xFF) / 255,
				green: CGFloat((rgbHexValue >> 8) & 0xFF) / 255,
				blue: CGFloat(rgbHexValue & 0xFF) / 255,
				alpha: isDark ? darkAlpha : lightAlpha
			)
		}
	}
	static func grayscaleColor(
		light: CGFloat,
		dark: CGFloat
	) -> NSColor
	{
		NSColor(name: nil)
		{
			appearance in
			NSColor(
				white: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
					? dark : light,
				alpha: 1
			)
		}
	}

	static func labMix(
		_ first: NSColor,
		_ second: NSColor,
		amount: Double
	) -> NSColor
	{
		func lab(_ input: NSColor) -> [Double]
		{
			let c = input.usingColorSpace(.sRGB) ?? input
			func linear(_ value: CGFloat) -> Double
			{
				let x = Double(value)
				return x <= 0.04045 ? x / 12.92 : pow(
					(x + 0.055) / 1.055,
					2.4
				)
			}
			let r = linear(c.redComponent), g = linear(c.greenComponent),
				b = linear(c.blueComponent)
			let x = (0.4360657469 * r + 0.3851514688 * g + 0.1430784544 * b) / 0.964295676
			let y = 0.2224931771 * r + 0.7168870131 * g + 0.0606198098 * b
			let z = (0.0139239215 * r + 0.0970813242 * g + 0.7140993584 * b) / 0.825104603
			func f(_ t: Double) -> Double
			{
				t > 216.0 / 24389 ? pow(
					t,
					1.0 / 3
				) : (841.0 / 108) * t +
					4.0 / 29
			}
			let fx = f(x), fy = f(y), fz = f(z)
			return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)]
		}
		let a = lab(first), b = lab(second)
		let values = zip(
			a,
			b
		).map
		{
			first, second in first + (second - first) * amount
		}
		let fy = (values[0] + 16) / 116, fx = fy + values[1] / 500, fz = fy - values[2] / 200
		func inverse(_ t: Double) -> Double
		{
			pow(
				t,
				3
			) > 216.0 / 24389 ? pow(
				t,
				3
			) : (
				108.0 / 841
			) *
				(t - 4.0 / 29)
		}
		let x = 0.964295676 * inverse(fx), y = inverse(fy), z = 0.825104603 * inverse(fz)
		func encode(_ x: Double) -> CGFloat
		{
			let value = x <= 0.0031308 ? 12.92 * x : 1.055 * pow(
				x,
				1.0 / 2.4
			) - 0.055
			return CGFloat(min(
				1,
				max(
					0,
					value
				)
			))
		}
		return NSColor(
			srgbRed: encode(3.1338561 * x - 1.6168667 * y - 0.4906146 * z),
			green: encode(-0.9787684 * x + 1.9161415 * y + 0.0334540 * z),
			blue: encode(0.0719453 * x - 0.2289914 * y + 1.4052427 * z),
			alpha: 1
		)
	}
	static func hexColor(_ hex: String) -> NSColor?
	{
		guard (hex.count == 7 || hex.count == 9), hex.first == "#",
				let value = UInt32(
				hex.dropFirst(),
				radix: 16
				)
		else
		{
			return nil
		}
		let rgb = hex.count == 9 ? value >> 8 : value
		let alpha = hex.count == 9 ? value & 255 : 255
		return NSColor(
			srgbRed: CGFloat((rgb >> 16) & 255) / 255,
			green: CGFloat((rgb >> 8) & 255) / 255,
			blue: CGFloat(rgb & 255) / 255,
			alpha: CGFloat(alpha) / 255
		)
	}

}

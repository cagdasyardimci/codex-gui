import AppKit

/// The reference content-color adjustment operates in OKLab after the chrome palette is resolved.
@MainActor
struct ColorContentPalette
{
	struct Lab: Equatable
	{
		let lightness: Double
		let a: Double
		let b: Double

		init(hex: UInt32)
		{
			func linear(_ x: UInt32) -> Double
			{
				let v = Double(x) / 255
				return v <= 0.04045 ? v / 12.92 : pow(
					(v + 0.055) / 1.055,
					2.4
				)
			}
			let r = linear((hex >> 16) & 255), g = linear((hex >> 8) & 255), b = linear(hex & 255)
			let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
			let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
			let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
			lightness = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s
			a = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s
			self.b = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s
		}

		init(
			lightness: Double,
			a: Double,
			b: Double
		)
		{
			self.lightness = lightness
			self.a = a
			self.b = b
		}

		var color: NSColor
		{
			let l = pow(
				lightness + 0.3963377774 * a + 0.2158037573 * b,
				3
			)
			let m = pow(
				lightness - 0.1055613458 * a - 0.0638541728 * b,
				3
			)
			let s = pow(
				lightness - 0.0894841775 * a - 1.2914855480 * b,
				3
			)
			func encoded(_ x: Double) -> CGFloat
			{
				let value = x <= 0.0031308 ? x * 12.92 : 1.055 * pow(
					x,
					1 / 2.4
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
				srgbRed: encoded(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
				green: encoded(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
				blue: encoded(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s),
				alpha: 1
			)
		}
	}

	private let under: UInt32
	private let foreground: UInt32
	private let dark: Bool

	init(
		surfaceUnder: NSColor,
		foreground: UInt32,
		mode: ColorAppearance
	)
	{
		let color = surfaceUnder.usingColorSpace(.sRGB)!
		func byte(_ component: CGFloat) -> UInt32
		{
			UInt32(min(
				255,
				max(
					0,
					(component * 255).rounded()
				)
			))
		}
		under = (byte(color.redComponent) << 16) | (byte(color.greenComponent) << 8) |
			byte(color.blueComponent)
		self.foreground = foreground
		dark = mode == .dark
	}

	func adapt(
		_ hex: UInt32,
		neutral: Bool = false
	) -> Lab
	{
		let start = Lab(hex: hex)
		let baseBackground: UInt32 = dark ? 0x0E0E0E : 0xF5F5F5
		let baseForeground: UInt32 = dark ? 0xFCFCFC : 0x0D0D0D
		guard under != baseBackground || foreground != baseForeground
		else
		{
			return start
		}
		let actual = Lab(hex: under), end = Lab(hex: foreground)
		let reference = Lab(hex: baseBackground), referenceEnd = Lab(hex: baseForeground)
		func round8(_ x: Double) -> Double
		{
			(x * 100_000_000).rounded() / 100_000_000
		}
		let position = min(
			1,
			max(
				0,
				(start.lightness - round8(reference.lightness)) /
					round8(referenceEnd.lightness - reference.lightness)
			)
		)
		func delta(
			_ current: Double,
			_ base: Double,
			_ target: Double,
			_ targetBase: Double
		) -> Double
		{
			let left = current - base
			let right = target - targetBase
			return round8(0.12 * left) + position * round8(0.12 * (right - left))
		}
		let dl = delta(
			actual.lightness,
			reference.lightness,
			end.lightness,
			referenceEnd.lightness
		)
		let da = delta(
			actual.a,
			reference.a,
			end.a,
			referenceEnd.a
		)
		let db = delta(
			actual.b,
			reference.b,
			end.b,
			referenceEnd.b
		)
		let scale = round8(min(
			1.03,
			max(
				0.97,
				1 + 0.1 *
					(abs(end.lightness - actual.lightness) -
						abs(referenceEnd.lightness - reference.lightness))
			)
		))
		let factor = neutral ? min(
			1,
			0.01 / max(
				hypot(
					da,
					db
				),
				0.00000001
			)
		) : 0
		return Lab(
			lightness: min(
				1,
				max(
					0,
					start.lightness + min(
						0.015,
						max(
							-0.015,
							dl
						)
					)
				)
			),
			a: start.a * scale + da * factor,
			b: start.b * scale + db * factor
		)
	}
}

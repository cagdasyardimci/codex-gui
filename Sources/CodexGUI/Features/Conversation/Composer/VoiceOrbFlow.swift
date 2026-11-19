import CoreGraphics
import Foundation

/// Samples flowing light at three depths inside a sphere. Both orb sizes share one frame cache.
enum VoiceOrbFlow
{
	static let duration: CFTimeInterval = 6
	private static let side = 128
	private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

	static func frames() -> [CGImage]
	{
		let frameCount = 144
		return (0 ..< frameCount).compactMap
		{
			frame(phase: Double($0) * 2 * .pi / Double(frameCount))
		}
	}

	static func frame(phase: Double = 0) -> CGImage?
	{
		raster(side: side)
		{
			x, y, depth in
			let color = shadeLiquid(
				x: x,
				y: y,
				depth: depth,
				phase: phase
			)
			return SIMD4(
				color.x,
				color.y,
				color.z,
				1
			)
		}
	}

	static func rippleFrames() -> [CGImage]
	{
		let count = 36
		return (0 ..< count).compactMap
		{
			index in
			let progress = Double(index) / Double(count - 1)
			let travel = 0.11 + 2 * progress
			let front = cos(travel)
			let wake = cos(max(
				0,
				travel - 0.16
			))
			let echo = cos(max(
				0,
				travel - 0.28
			))
			let fade = min(
				1,
				progress * 8
			) * (1 - progress) * (1 - progress)
			return raster(side: 96)
			{
				x, y, depth in
				// The wave spreads along the sphere from a point on the near side.
				let projection = -0.52 * x + 0.52 * y + 0.677 * depth
				let bend = sin(8 * x + 5 * y - 6 * progress)
				let distance = projection - front + 0.032 * bend
				let crest = exp(-distance * distance * 1050)
				let echoDistance = projection - echo - 0.022 * bend
				let echoLight = exp(-800 * echoDistance * echoDistance) *
					(0.13 + 0.15 * bend * bend)
				let trail = projection - wake
				let trough = exp(-trail * trail * 410) * 0.32
				let light = 0.54 + 0.46 * max(
					0,
					0.62 * depth - 0.72 * x
				)
				let highlight = (crest + echoLight) * light
				let whiteness = highlight / max(
					0.0001,
					highlight + trough
				)
				return SIMD4(
					0.16 + 0.66 * whiteness,
					0.29 + 0.69 * whiteness,
					0.53 + 0.47 * whiteness,
					(highlight * 0.68 + trough * 0.55) * fade
				)
			}
		}
	}

	private static func raster(
		side: Int,
		shade: (Double, Double, Double) -> SIMD4<Double>
	) -> CGImage?
	{
		let rowBytes = side * 4
		let step = 2 / Double(side)
		var pixels = [UInt8](
			repeating: 0,
			count: rowBytes * side
		)
		for row in 0 ..< side
		{
			let y = (Double(row) + 0.5) * step - 1
			for column in 0 ..< side
			{
				let x = (Double(column) + 0.5) * step - 1
				let depthSquared = 1 - x * x - y * y
				guard depthSquared > 0
				else
				{
					continue
				}
				let depth = sqrt(depthSquared)

				let liquid = shade(
					x,
					y,
					depth
				)
				let alpha = min(
					1,
					depthSquared * Double(side)
				) * liquid.w

				let pixel = row * rowBytes + column * 4
				pixels[pixel] = byte(
					liquid.x,
					alpha: alpha
				)
				pixels[pixel + 1] = byte(
					liquid.y,
					alpha: alpha
				)
				pixels[pixel + 2] = byte(
					liquid.z,
					alpha: alpha
				)
				pixels[pixel + 3] = UInt8(alpha * 255)
			}
		}
		guard let provider = CGDataProvider(data: Data(pixels) as CFData)
		else
		{
			return nil
		}
		return CGImage(
			width: side,
			height: side,
			bitsPerComponent: 8,
			bitsPerPixel: 32,
			bytesPerRow: rowBytes,
			space: colorSpace,
			bitmapInfo: [
				.byteOrder32Big,
				CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
			],
			provider: provider,
			decode: nil,
			shouldInterpolate: true,
			intent: .defaultIntent
		)
	}

	private static func shadeLiquid(
		x: Double,
		y: Double,
		depth: Double,
		phase: Double
	) -> SIMD3<Double>
	{
		// Move one broad fold through the sphere. Its displaced coordinates also
		// bend the smaller currents, carrying the fine detail along with the fold.
		let angle = 0.72 + 0.28 * sin(phase)
		let axis = SIMD2(
			cos(angle),
			sin(angle)
		)
		let normal = SIMD2(
			-axis.y,
			axis.x
		)
		let across = x * normal.x + y * normal.y
		let along = x * axis.x + y * axis.y
		let fold = across + 0.29 * sin(2.7 * along + phase)
			+ 0.10 * sin(5.5 * along - 2 * phase) - 0.28 * sin(phase - 0.65)
		let shoulder = exp(-5 * fold * fold)
		let curl = sin(4 * along - phase) * shoulder
		let point = SIMD2(
			x,
			y
		) + depth * (normal * (0.23 * shoulder) + axis * (0.16 * curl))
		let refraction = point * (0.28 * depth)
		let front = currents(
			point + refraction,
			depth: depth * 0.78,
			phase: phase
		)
		let middle = currents(
			point,
			depth: 0,
			phase: phase - 0.45
		)
		let back = currents(
			point - refraction,
			depth: -depth * 0.8,
			phase: 0.7 - phase
		)

		// A pale crest gives the broad fold a readable silhouette in the pill.
		// The fine highlights are strongest where that fold catches the light.
		let crestDistance = fold - 0.18
		let crest = exp(-17 * crestDistance * crestDistance) * (0.46 + 0.54 * depth)
		let body = 0.20 * front.x + 0.31 * middle.x + 0.26 * back.x
		let glints = (0.53 * front.y + 0.33 * middle.y + 0.14 * back.y) * (0.47 + 0.50 * crest)
		let caustic = focusedLight(
			point + refraction,
			depth: depth,
			phase: phase
		)
		let basin = 0.5 + 0.5 * sin(3.5 * across - 2.3 * along + 1.6 * curl - phase - 2 * depth)
		let shading = max(
			0,
			-0.35 * x - 0.42 * y + 0.8 * depth
		)
		let sky = SIMD3(
			0.18,
			0.28,
			0.39
		) * shading
		let cobalt = SIMD3(
			0.055 + 0.065 * basin,
			0.10 + 0.085 * basin,
			0.35 + 0.17 * basin + 0.04 * back.x
		)
		let currentColor = SIMD3(
			0.13,
			0.43,
			0.54
		) * body
		let highlights = SIMD3(
			0.40,
			0.48,
			0.39
		) * glints

		let edge = 1 - depth
		let rim = edge * edge * (0.09 + 0.24 * max(
			0,
			0.5 * x - 0.8 * y
		))
		let reflection = pow(
			max(
				0,
				-0.31 * x - 0.55 * y + 0.77 * depth
			),
			26
		) * 0.20
		let foldLight = SIMD3(
			0.28,
			0.36,
			0.34
		) * crest
		let causticLight = SIMD3(
			0.41,
			0.64,
			0.52
		) * (caustic * (0.48 + 0.52 * crest))
		return cobalt + sky + currentColor + highlights + foldLight + causticLight + SIMD3(
			0.28,
			0.51,
			0.86
		) * rim
			+ SIMD3(
				0.80,
				0.89,
				1
			) * reflection
	}

	/// As two warped wave fields cross, their crests focus into a moving network of light.
	private static func focusedLight(
		_ point: SIMD2<Double>,
		depth: Double,
		phase: Double
	) -> Double
	{
		let u = point.x + 0.24 * sin(3.5 * point.y + phase + depth)
		let v = point.y + 0.21 * sin(4.2 * point.x - phase + 1.3 * depth)
		let firstWave = sin(7.6 * u + 3.2 * v + 2 * phase)
		let secondWave = sin(2.7 * u - 8.8 * v - phase + 1.9 * depth)
		let intersection = firstWave + 0.74 * secondWave
		let halo = 1 / (1 + 30 * intersection * intersection)
		let filament = halo * halo
		let light = 0.5 + 0.5 * sin(4.6 * u - 1.5 * v + phase)
		return (0.27 * halo + 0.73 * filament) * light * depth
	}

	private static func currents(
		_ point: SIMD2<Double>,
		depth: Double,
		phase: Double
	) -> SIMD2<Double>
	{
		// The apparent center of the eddy drifts with phase and depth.
		let vortex = SIMD2(
			0.30 * sin(phase + depth),
			0.24 * cos(phase - 1.7 * depth)
		)
		let offset = point - vortex
		let radius = offset.x * offset.x + offset.y * offset.y
		let curl = (0.75 + 0.33 * cos(2 * phase + depth)) / (0.46 + radius)
		let sine = sin(curl)
		let cosine = cos(curl)
		let swirled = vortex + SIMD2(
			offset.x * cosine - offset.y * sine,
			offset.x * sine + offset.y * cosine
		)
		let u = swirled.x + 0.16 * sin(5.3 * swirled.y - phase + depth)
		let v = swirled.y + 0.20 * sin(3.6 * u + phase - depth)
		let band = sin(4.2 * v + 1.35 * sin(3.1 * u - phase) + 2.5 * depth)
		let ripples = sin(7 * u - 3.6 * v + 2 * phase + 2.1 * depth)
		let density = 1 / (1 + 2.1 * band * band)
		let brightEdge = band - 0.19 * ripples
		let glint = (0.44 + 0.56 * max(
			0,
			ripples
		)) / (1 + 25 * brightEdge * brightEdge)
		return SIMD2(
			density,
			glint
		)
	}

	private static func byte(
		_ value: Double,
		alpha: Double
	) -> UInt8
	{
		UInt8(min(
			1,
			max(
				0,
				value
			)
		) * alpha * 255)
	}
}

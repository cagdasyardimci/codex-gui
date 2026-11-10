import Foundation

/// Coordinates are fractions of the original image, measured from its top-left corner.
struct ImageAnnotation: Codable, Equatable, Identifiable
{
	let id: String
	let x: Double
	let y: Double
	var text: String

	init(
		id: String = UUID().uuidString,
		x: Double,
		y: Double,
		text: String
	)
	{
		self.id = id
		self.x = x
		self.y = y
		self.text = text
	}

	var isValid: Bool
	{
		x.isFinite && y.isFinite && (0 ... 1).contains(x) && (0 ... 1).contains(y)
			&& !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}

	var coordinateDescription: String
	{
		func percentage(_ value: Double) -> String
		{
			let rounded = (value * 1000).rounded() / 10
			return rounded.formatted(.number.locale(Locale(identifier: "en_US_POSIX"))
				.precision(.fractionLength(0 ... 1)).grouping(.never))
		}
		return "(x: \(percentage(x))%, y: \(percentage(y))%)"
	}
}

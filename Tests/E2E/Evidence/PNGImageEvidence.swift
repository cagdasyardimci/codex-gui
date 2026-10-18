import Foundation
import ImageIO

func pngDimensions(_ url: URL) throws -> (Int, Int)
{
	let dimensions = try validatedPNGDimensions(Data(contentsOf: url))
	guard let source = CGImageSourceCreateWithURL(
		url as CFURL,
		nil
	),
		CGImageSourceCreateImageAtIndex(
			source,
			0,
			nil
		) != nil
	else
	{
		throw EvidenceError.invalid("PNG pixels could not be decoded")
	}
	return dimensions
}

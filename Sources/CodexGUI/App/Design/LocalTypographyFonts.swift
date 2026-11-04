import AppKit
import CoreText

/// Registers a user-provided font without redistributing the licensed font data.
@MainActor
enum LocalTypographyFonts
{
	private static var attemptedRegistration = false

	static func registerOpenAISans()
	{
		guard !attemptedRegistration
		else
		{
			return
		}
		attemptedRegistration = true
		guard NSFont(
			name: "OpenAISans-Semibold",
			size: 18
		) == nil
		else
		{
			return
		}
		guard let library = FileManager.default.urls(
			for: .libraryDirectory,
			in: .userDomainMask
		)
		.first
		else
		{
			return
		}
		let url = library.appendingPathComponent("Fonts/OpenAISans-Semibold.woff2")
		guard FileManager.default.fileExists(atPath: url.path)
		else
		{
			return
		}
		CTFontManagerRegisterFontsForURL(
			url as CFURL,
			.process,
			nil
		)
	}
}

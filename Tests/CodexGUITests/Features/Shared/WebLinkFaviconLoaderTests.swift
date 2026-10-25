import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import CodexGUI

@Suite(.timeLimit(.minutes(1)))
struct WebLinkFaviconLoaderTests
{
	@Test func googleIconRequestUsesValidatedHostAnd256Pixels() throws
	{
		let page = try #require(URL(string: "https://astro.build/blog/post?query=1"))
		let origin = try #require(WebLinkFaviconLoader.originURL(for: page))
		#expect(origin.absoluteString == "https://astro.build/")
		let icon = try #require(WebLinkFaviconLoader.googleIconURL(for: origin))
		#expect(icon.absoluteString ==
			"https://www.google.com/s2/favicons?domain=astro.build&sz=256")
	}

	@Test func unsafeOriginsAreIgnored() throws
	{
		for value in [
			"file:///tmp/page.html",
			"https://localhost/page",
			"https://site.local/page",
			"https://user@site.example/page",
			"https://site.example:8443/page",
		]
		{
			let url = try #require(URL(string: value))
			#expect(WebLinkFaviconLoader.originURL(for: url) == nil)
		}
	}

	@Test func onlyGoogleFaviconRedirectsReachGstatic() throws
	{
		let original = try #require(URL(string:
			"https://www.google.com/s2/favicons?domain=astro.build&sz=256"))
		let allowed = try #require(URL(string:
			"https://t2.gstatic.com/faviconV2?size=256"))
		#expect(WebLinkFaviconLoader.allowsGoogleRedirect(
			from: original,
			to: allowed
		))
		for value in [
			"http://t2.gstatic.com/faviconV2?size=256",
			"https://evil.gstatic.com/faviconV2?size=256",
			"https://t2.gstatic.com/other",
			"https://t2.gstatic.com.evil.example/faviconV2",
			"https://user@t2.gstatic.com/faviconV2",
			"https://t2.gstatic.com:8443/faviconV2",
		]
		{
			let destination = try #require(URL(string: value))
			#expect(!WebLinkFaviconLoader.allowsGoogleRedirect(
				from: original,
				to: destination
			))
		}
	}

	@Test func unsafePagesNeverReachEitherIconSource() async throws
	{
		let calls = FaviconSourceCalls()
		let loader = WebLinkFaviconLoader(
			googleIcon:
			{
				await calls.google($0)
				return nil
			},
			metadata:
			{
				await calls.metadata($0)
				return nil
			}
		)
		for value in ["file:///tmp/icon.png", "https://site.local/", "https://site.example:8443/"]
		{
			let page = try #require(URL(string: value))
			#expect(await loader.favicon(for: page) == nil)
		}
		#expect(await calls.googleURLs.isEmpty)
		#expect(await calls.metadataURLs.isEmpty)
	}

	private func padded(
		_ data: Data,
		to count: Int
	) -> Data
	{
		data + Data(
			repeating: 0,
			count: count - data.count
		)
	}

	private func iconData(red: CGFloat) throws -> Data
	{
		let context = try #require(CGContext(
			data: nil,
			width: 2,
			height: 2,
			bitsPerComponent: 8,
			bytesPerRow: 8,
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		))
		context.setFillColor(CGColor(
			red: red,
			green: 0,
			blue: 1 - red,
			alpha: 1
		))
		context.fill(CGRect(
			x: 0,
			y: 0,
			width: 2,
			height: 2
		))
		let image = try #require(context.makeImage())
		let data = NSMutableData()
		let destination = try #require(CGImageDestinationCreateWithData(
			data,
			UTType.png.identifier as CFString,
			1,
			nil
		))
		CGImageDestinationAddImage(
			destination,
			image,
			nil
		)
		try #require(CGImageDestinationFinalize(destination))
		return data as Data
	}
}

private actor FaviconSourceCalls
{
	private(set) var googleURLs: [String] = []
	private(set) var metadataURLs: [String] = []

	func google(_ url: URL)
	{
		googleURLs.append(url.absoluteString)
	}

	func metadata(_ url: URL)
	{
		metadataURLs.append(url.absoluteString)
	}
}

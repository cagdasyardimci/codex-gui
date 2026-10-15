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

	@Test func validGoogleImageIsReturnedAndCachedForTheOrigin() async throws
	{
		let bytes = try iconData(red: 1)
		let calls = FaviconSourceCalls()
		let loader = WebLinkFaviconLoader(
			googleIcon:
			{
				await calls.google($0)
				return bytes
			},
			metadata:
			{
				await calls.metadata($0)
				return nil
			}
		)
		let page = try #require(URL(string: "https://site.example/one?query=1"))
		let otherPage = try #require(URL(string: "https://site.example/two"))
		#expect(await loader.favicon(for: page) == bytes)
		#expect(await loader.favicon(for: otherPage) == bytes)
		#expect(await calls.googleURLs == [
			"https://www.google.com/s2/favicons?domain=site.example&sz=256"
		])
		#expect(await calls.metadataURLs.isEmpty)
	}

	@Test(arguments: ["missing", "empty", "invalid", "oversized"])
	func unusableGoogleResponsesFallBackToRealMetadataImages(_ response: String) async throws
	{
		let bytes = try iconData(red: 0)
		let googleBytes: Data? = switch response
		{
		case "missing": nil
		case "empty": Data()
		case "invalid": Data("not an image".utf8)
		default: padded(
				bytes,
				to: 131_073
			)
		}
		let calls = FaviconSourceCalls()
		let loader = WebLinkFaviconLoader(
			googleIcon:
			{
				await calls.google($0)
				return googleBytes
			},
			metadata:
			{
				await calls.metadata($0)
				return bytes
			}
		)
		let page = try #require(URL(string: "https://fallback.example/article"))
		#expect(await loader.favicon(for: page) == bytes)
		#expect(await loader.favicon(for: page) == bytes)
		#expect(await calls.googleURLs.count == 1)
		#expect(await calls.metadataURLs == ["https://fallback.example/"])
	}

	@Test(arguments: ["missing", "empty", "invalid", "oversized"])
	func unusableMetadataResponsesAreCachedAsMissing(_ response: String) async throws
	{
		let metadataBytes: Data? = switch response
		{
		case "missing": nil
		case "empty": Data()
		case "invalid": Data("not an image".utf8)
		default: try padded(
				iconData(red: 0),
				to: 131_073
			)
		}
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
				return metadataBytes
			}
		)
		let page = try #require(URL(string: "https://missing.example/article"))
		#expect(await loader.favicon(for: page) == nil)
		#expect(await loader.favicon(for: page) == nil)
		#expect(await calls.googleURLs.count == 1)
		#expect(await calls.metadataURLs == ["https://missing.example/"])
	}

	@Test(arguments: [true, false])
	func theByteLimitIncludesExactly128KiB(_ google: Bool) async throws
	{
		let bytes = try padded(
			iconData(red: 1),
			to: 131_072
		)
		let calls = FaviconSourceCalls()
		let loader = WebLinkFaviconLoader(
			googleIcon:
			{
				await calls.google($0)
				return google ? bytes : nil
			},
			metadata:
			{
				await calls.metadata($0)
				return bytes
			}
		)
		let page = try #require(URL(string: "https://limit.example/"))
		#expect(await loader.favicon(for: page) == bytes)
		#expect(await calls.googleURLs.count == 1)
		#expect(await calls.metadataURLs.count == (google ? 0 : 1))
	}

	@Test func concurrentPagesShareTheirPendingOriginRequest() async throws
	{
		let bytes = try iconData(red: 1)
		let calls = FaviconSourceCalls()
		let (started, startedSignal) = AsyncStream<Void>.makeStream()
		let (release, releaseSignal) = AsyncStream<Void>.makeStream()
		defer
		{
			startedSignal.finish()
			releaseSignal.finish()
		}
		let loader = WebLinkFaviconLoader(
			googleIcon:
			{
				await calls.google($0)
				startedSignal.yield(())
				for await _ in release
				{
					break
				}
				return bytes
			},
			metadata:
			{
				_ in nil
			}
		)
		let firstPage = try #require(URL(string: "https://shared.example/first"))
		let secondPage = try #require(URL(string: "https://shared.example/second"))
		let first = await loader.request(for: firstPage)
		var start = started.makeAsyncIterator()
		try #require(await start.next() != nil)
		// Register the second request while the actual first source remains suspended.
		let second = await loader.request(for: secondPage)
		releaseSignal.finish()
		#expect(await first.value == bytes)
		#expect(await second.value == bytes)
		#expect(await loader.favicon(for: secondPage) == bytes)
		#expect(await calls.googleURLs.count == 1)
		#expect(await calls.metadataURLs.isEmpty)
	}

	@Test func cacheEvictsTheOldestOriginAfter128Sites() async throws
	{
		let bytes = try iconData(red: 1)
		let calls = FaviconSourceCalls()
		let loader = WebLinkFaviconLoader(
			googleIcon:
			{
				await calls.google($0)
				return bytes
			},
			metadata:
			{
				_ in nil
			}
		)
		for index in 0 ..< 129
		{
			let page = try #require(URL(string: "https://site-\(index).example/"))
			#expect(await loader.favicon(for: page) == bytes)
		}
		let retained = try #require(URL(string: "https://site-1.example/another"))
		#expect(await loader.favicon(for: retained) == bytes)
		#expect(await calls.googleURLs.count == 129)
		let evicted = try #require(URL(string: "https://site-0.example/another"))
		#expect(await loader.favicon(for: evicted) == bytes)
		#expect(await calls.googleURLs.count == 130)
		#expect(await calls.googleURLs.last ==
			"https://www.google.com/s2/favicons?domain=site-0.example&sz=256")
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

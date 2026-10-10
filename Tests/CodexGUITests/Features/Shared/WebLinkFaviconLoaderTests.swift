import Foundation
import Testing

@testable import CodexGUI

@Suite
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
}

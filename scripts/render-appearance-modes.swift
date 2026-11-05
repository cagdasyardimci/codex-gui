import AppKit
import WebKit

/// Prepare fixed illustration plates once; live accent marks remain native template masks.
@main
struct RenderAppearanceModes
{
	@MainActor static func main() async throws
	{
		_ = NSApplication.shared
		let directory = URL(
			fileURLWithPath: CommandLine.arguments[1],
			isDirectory: true
		)
		let renderer = PlateRenderer()
		for name in ["Light", "Dark"]
		{
			let source = try String(
				contentsOf: directory.appendingPathComponent(name + ".svg"),
				encoding: .utf8
			)
			let xml = try XMLDocument(xmlString: source)
			let marks = try xml.nodes(forXPath: "//*[@fill='currentColor']")
			let mask = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"80\" height=\"60\""
				+ " viewBox=\"0 0 80 60\">"
				+ marks.map
				{
					$0.xmlString.replacingOccurrences(
						of: "currentColor",
						with: "black"
					)
				}
				.joined()
				+ "</svg>\n"
			try mask.write(
				to: directory.appendingPathComponent(name + "Accent.svg"),
				atomically: true,
				encoding: .utf8
			)
			let pdf = try await renderer.render(source.replacingOccurrences(
				of: "currentColor",
				with: "none"
			))
			try pdf.write(
				to: directory.appendingPathComponent(name + ".pdf"),
				options: .atomic
			)
			print("Prepared \(name) plate and accent mask")
		}
	}
}

@MainActor
private final class PlateRenderer: NSObject, WKNavigationDelegate
{
	private let view: WKWebView
	private var loaded: CheckedContinuation<Void, Error>?

	override init()
	{
		let configuration = WKWebViewConfiguration()
		configuration.websiteDataStore = .nonPersistent()
		view = WKWebView(
			frame: NSRect(
				x: 0,
				y: 0,
				width: 80,
				height: 60
			),
			configuration: configuration
		)
		super.init()
		view.navigationDelegate = self
	}

	func render(_ svg: String) async throws -> Data
	{
		try await withCheckedThrowingContinuation
		{
			loaded = $0
			let html = "<html><head><meta name=\"color-scheme\" content=\"light\"><style>"
				+ "html,body{margin:0;width:80px;height:60px;background:transparent}"
				+ "svg{display:block}</style></head><body>" + svg + "</body></html>"
			view.loadHTMLString(
				html,
				baseURL: nil
			)
		}
		let configuration = WKPDFConfiguration()
		configuration.allowTransparentBackground = true
		configuration.rect = NSRect(
			x: 0,
			y: 0,
			width: 80,
			height: 60
		)
		return try await view.pdf(configuration: configuration)
	}

	func webView(
		_ webView: WKWebView,
		didFinish navigation: WKNavigation!
	)
	{
		loaded?.resume()
		loaded = nil
	}

	func webView(
		_ webView: WKWebView,
		didFailProvisionalNavigation navigation: WKNavigation!,
		withError error: Error
	)
	{
		loaded?.resume(throwing: error)
		loaded = nil
	}
}

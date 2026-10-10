import AppKit
import LinkPresentation
import UniformTypeIdentifiers

/// Loads small site icons on demand. A failed request is cached for this app session.
actor WebLinkFaviconLoader
{
	static let shared = WebLinkFaviconLoader()
	private enum Entry
	{
		case image(Data)
		case missing
	}

	private var entries: [String: Entry] = [:]
	private var order: [String] = []
	private var pending: [String: Task<Data?, Never>] = [:]
	private let capacity = 128
	private static let iconByteLimit = 131_072

	func favicon(for url: URL) async -> Data?
	{
		guard let origin = Self.originURL(for: url),
				let host = origin.host, let scheme = origin.scheme
		else
		{
			return nil
		}
		let key = scheme + "://" + host.lowercased()
		if let entry = entries[key]
		{
			switch entry
			{
			case let .image(data): return data
			case .missing: return nil
			}
		}
		if let task = pending[key]
		{
			return await task.value
		}
		let task = Task<Data?, Never>
		{
			if let googleURL = Self.googleIconURL(for: origin),
				let data = await Self.downloadGoogleIcon(googleURL),
				Self.isUsableImage(data)
			{
				return data
			}
			return await Self.metadataIcon(for: origin)
		}
		pending[key] = task
		let data = await task.value
		pending[key] = nil
		entries[key] = data.map(Entry.image) ?? .missing
		order.append(key)
		if order.count > capacity
		{
			entries.removeValue(forKey: order.removeFirst())
		}
		return data
	}

	static func originURL(for url: URL) -> URL?
	{
		guard url.scheme == "https" || url.scheme == "http",
				let host = url.host?.lowercased(),
				host.contains("."), !host.hasSuffix(".local"),
				!host.contains(":"),
				host.rangeOfCharacter(from: .letters) != nil,
				url.port == nil, url.user == nil, url.password == nil
		else
		{
			return nil
		}
		var components = URLComponents()
		components.scheme = url.scheme
		components.host = host
		components.path = "/"
		return components.url
	}

	static func googleIconURL(for origin: URL) -> URL?
	{
		guard let host = origin.host
		else
		{
			return nil
		}
		var components = URLComponents()
		components.scheme = "https"
		components.host = "www.google.com"
		components.path = "/s2/favicons"
		components.queryItems = [
			URLQueryItem(
				name: "domain",
				value: host
			),
			URLQueryItem(
				name: "sz",
				value: "256"
			),
		]
		return components.url
	}

	private static func downloadGoogleIcon(_ url: URL) async -> Data?
	{
		let configuration = URLSessionConfiguration.ephemeral
		configuration.httpShouldSetCookies = false
		configuration.httpCookieStorage = nil
		configuration.urlCache = nil
		configuration.timeoutIntervalForRequest = 3
		configuration.timeoutIntervalForResource = 3
		let session = URLSession(
			configuration: configuration,
			delegate: GoogleFaviconRedirectDelegate(),
			delegateQueue: nil
		)
		defer
		{
			session.invalidateAndCancel()
		}
		var request = URLRequest(url: url)
		request.setValue(
			"image/png",
			forHTTPHeaderField: "Accept"
		)
		guard let (bytes, response) = try? await session.bytes(for: request),
				let response = response as? HTTPURLResponse,
				response.statusCode == 200
		else
		{
			return nil
		}
		var data = Data()
		do
		{
			for try await byte in bytes
			{
				guard data.count < iconByteLimit
				else
				{
					return nil
				}
				data.append(byte)
			}
		}
		catch
		{
			return nil
		}
		guard !data.isEmpty
		else
		{
			return nil
		}
		return data
	}

	private static func isUsableImage(_ data: Data) -> Bool
	{
		guard data.count <= iconByteLimit, let image = NSImage(data: data)
		else
		{
			return false
		}
		return !image.representations.isEmpty
	}

	private static func metadataIcon(for origin: URL) async -> Data?
	{
		let data: Data? = await withCheckedContinuation
		{
			continuation in
			let provider = LPMetadataProvider()
			provider.shouldFetchSubresources = true
			provider.timeout = 5
			provider.startFetchingMetadata(for: origin)
			{
				metadata, _ in
				guard let icon = metadata?.iconProvider,
						let type = icon.registeredTypeIdentifiers.first(where:
						{
							identifier in
							UTType(identifier)?.conforms(to: .image) == true
						})
				else
				{
					continuation.resume(returning: nil)
					return
				}
				_ = icon.loadDataRepresentation(forTypeIdentifier: type)
				{
					data, _ in
					continuation.resume(returning: data)
				}
			}
		}
		guard let data, isUsableImage(data)
		else
		{
			return nil
		}
		return data
	}

	static func allowsGoogleRedirect(
		from original: URL,
		to destination: URL
	) -> Bool
	{
		guard original.scheme == "https", original.host == "www.google.com",
				original.path == "/s2/favicons",
				destination.scheme == "https", destination.port == nil,
				destination.user == nil, destination.password == nil
		else
		{
			return false
		}
		if destination.host == "www.google.com"
		{
			return destination.path == "/s2/favicons"
		}
		guard let host = destination.host, host.hasSuffix(".gstatic.com"),
				host.first == "t", destination.path == "/faviconV2"
		else
		{
			return false
		}
		let digits = host.dropFirst().prefix(while: \.isNumber)
		return !digits.isEmpty && host == "t\(digits).gstatic.com"
	}
}

private final class GoogleFaviconRedirectDelegate: NSObject, URLSessionTaskDelegate,
	@unchecked Sendable
{
	func urlSession(
		_ session: URLSession,
		task: URLSessionTask,
		willPerformHTTPRedirection response: HTTPURLResponse,
		newRequest request: URLRequest,
		completionHandler: @escaping (URLRequest?) -> Void
	)
	{
		guard let original = task.originalRequest?.url,
				let destination = request.url,
				WebLinkFaviconLoader.allowsGoogleRedirect(
				from: original,
				to: destination
				)
		else
		{
			completionHandler(nil)
			return
		}
		completionHandler(request)
	}
}

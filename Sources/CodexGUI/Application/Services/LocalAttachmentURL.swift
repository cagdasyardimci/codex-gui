import Foundation

/// Accepts explicit local paths and local file URLs; remote URLs are never fetched.
enum LocalAttachmentURL
{
	/// Normalize lexical local-path aliases while preserving the Unicode bytes of every
	/// component. Actual filesystem URL resolution remains independent of reference identity.
	static func referenceIdentity(_ path: String) -> Data
	{
		let localPath: String
		if path.hasPrefix("file:")
		{
			guard let components = URLComponents(string: path), components.scheme == "file"
			else
			{
				return Data(path.utf8)
			}
			let host = components.host ?? ""
			guard host.isEmpty || host == "localhost",
					let decoded = components.percentEncodedPath.removingPercentEncoding,
					decoded.utf8.first == 0x2F
			else
			{
				return Data(path.utf8)
			}
			localPath = decoded
		}
		else if path.utf8.first == 0x7E
		{
			let bytes = Array(path.utf8)
			let prefixEnd = bytes.firstIndex(of: 0x2F) ?? bytes.endIndex
			let prefix = String(
				decoding: bytes[..<prefixEnd],
				as: UTF8.self
			)
			let home = NSString(string: prefix).expandingTildeInPath
			guard home.utf8.first == 0x2F
			else
			{
				return Data(path.utf8)
			}
			// Expanding only the home prefix keeps Foundation from rewriting the filename.
			localPath = home + String(
				decoding: bytes[prefixEnd...],
				as: UTF8.self
			)
		}
		else
		{
			guard path.utf8.first == 0x2F
			else
			{
				return Data(path.utf8)
			}
			localPath = path
		}
		let bytes = Array(localPath.utf8)
		var components: [ArraySlice<UInt8>] = []
		for component in bytes.split(separator: 0x2F)
		{
			if component.elementsEqual([0x2E])
			{
				continue
			}
			if component.elementsEqual([0x2E, 0x2E])
			{
				if !components.isEmpty
				{
					components.removeLast()
				}
			}
			else
			{
				components.append(component)
			}
		}
		var identity = Data([0x2F])
		for (index, component) in components.enumerated()
		{
			if index > 0
			{
				identity.append(0x2F)
			}
			identity.append(contentsOf: component)
		}
		return identity
	}

	static func resolve(_ path: String) -> URL?
	{
		if path.hasPrefix("file:")
		{
			guard let url = URL(string: path), url.isFileURL,
					url.host == nil || url.host == "" || url.host == "localhost",
					NSString(string: url.path).isAbsolutePath
			else
			{
				return nil
			}
			return URL(fileURLWithPath: url.path).standardizedFileURL
		}
		let expanded = NSString(string: path).expandingTildeInPath
		guard NSString(string: expanded).isAbsolutePath
		else
		{
			return nil
		}
		return URL(fileURLWithPath: expanded).standardizedFileURL
	}
}

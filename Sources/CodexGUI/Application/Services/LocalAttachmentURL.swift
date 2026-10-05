import Foundation

/// Accepts explicit local paths and local file URLs; remote URLs are never fetched.
enum LocalAttachmentURL
{
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

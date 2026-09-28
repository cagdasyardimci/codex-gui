import Foundation

/// Checkout identity follows the filesystem target, including symbolic-link aliases.
enum CheckoutIdentity
{
	static func validate(
		cwd: String,
		expectedDirectory: URL?
	) throws
	{
		guard let expectedDirectory
		else
		{
			return
		}
		guard cwd.hasPrefix("/"),
				canonicalPath(URL(fileURLWithPath: cwd)) == canonicalPath(expectedDirectory)
		else
		{
			throw AppServerError.protocolError("This conversation belongs to another checkout.")
		}
	}

	private static func canonicalPath(_ directory: URL) -> String
	{
		directory.standardizedFileURL.resolvingSymlinksInPath().path
	}
}

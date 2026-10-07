import Foundation
import CryptoKit
func digest(
	_ directory: URL,
	paths: [String]
) throws -> String
{
	var hash = SHA256()
	for path in Set(paths).sorted() where !path.isEmpty
	{
		hash.update(data: Data((path + "\0").utf8))
		let url = directory.appendingPathComponent(path)
		var isDirectory: ObjCBool = false
		let exists = FileManager.default.fileExists(
			atPath: url.path,
			isDirectory: &isDirectory
		)
		hash
			.update(data: exists && !isDirectory
				.boolValue ? try Data(contentsOf: url) : Data("<missing>".utf8))
	}
	return hash.finalize().map
	{
		String(
			format: "%02x",
			$0
		)
	}.joined()
}
func filePaths(
	_ directory: URL,
	ignoringPythonCaches: Bool = false
) throws -> [String]
{
	guard let enumerator = FileManager.default.enumerator(
		at: directory,
		includingPropertiesForKeys: [.isRegularFileKey]
	)
	else
	{
		throw ToolError.invalid("Cannot enumerate bundle: \(directory.path)")
	}
	var paths: [String] = []
	for case let url as URL in enumerator
	{
		if ignoringPythonCaches,
			url.pathComponents.contains("__pycache__") || url.pathExtension == "pyc"
		{
			enumerator.skipDescendants()
			continue
		}
		var isDirectory: ObjCBool = false
		if FileManager.default.fileExists(
			atPath: url.path,
			isDirectory: &isDirectory
		),
			!isDirectory.boolValue
		{
			paths.append(String(url.path.dropFirst(directory.path.count + 1)))
		}
	}
	return paths
}

func bundleDigest(_ directory: URL) throws -> String
{
	try digest(
		directory,
		paths: filePaths(directory)
	)
}

func sourceDigest(_ root: URL) throws -> String
{
	let paths = try command([
		"git",
		"-C",
		root.path,
		"ls-files",
		"-z",
		"--cached",
		"--others",
		"--exclude-standard",
	]).1.split(separator: "\0").map(String.init)
	return try digest(
		root,
		paths: paths
	)
}

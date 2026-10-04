import Foundation
import Testing

@testable import CodexGUI

struct ProjectFileIndexWatchScopeTests
{
	@Test func relativeAliasDestinationsAndTheirParentsAreObserved() throws
	{
		let directory = try makeTemporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let links = directory.appendingPathComponent(
			"links",
			isDirectory: true
		)
		let targets = directory.appendingPathComponent(
			"targets",
			isDirectory: true
		)
		let first = targets.appendingPathComponent(
			"first",
			isDirectory: true
		)
		let second = targets.appendingPathComponent(
			"second",
			isDirectory: true
		)
		for project in [links, first, second]
		{
			try FileManager.default.createDirectory(
				at: project,
				withIntermediateDirectories: true
			)
		}
		let destinationAlias = links.appendingPathComponent("destination")
		let checkoutAlias = directory.appendingPathComponent("checkout")
		try FileManager.default.createSymbolicLink(
			atPath: destinationAlias.path,
			withDestinationPath: "../targets/first"
		)
		try FileManager.default.createSymbolicLink(
			atPath: checkoutAlias.path,
			withDestinationPath: "links/destination"
		)
		let scope = try #require(ProjectFileIndexWatchScope
			.capture(projectPath: checkoutAlias.path))
		let firstIdentity = try #require(ProjectFileIndexWatchScope
			.DirectoryIdentity(path: first.path))
		let linkParent = try #require(ProjectFileIndexWatchScope
			.DirectoryIdentity(path: links.path))
		#expect(scope.root == firstIdentity)
		#expect(scope.parentDirectories.contains(linkParent))
		#expect(scope.isCurrent)

		try FileManager.default.removeItem(at: destinationAlias)
		try FileManager.default.createSymbolicLink(
			atPath: destinationAlias.path,
			withDestinationPath: "../targets/second"
		)
		#expect(!scope.isCurrent)
		let rebound = try #require(
			ProjectFileIndexWatchScope.capture(projectPath: checkoutAlias.path)
		)
		#expect(rebound.root == ProjectFileIndexWatchScope.DirectoryIdentity(path: second.path))
	}

	@Test func replacedRootIdentityChangesWhileSiblingWritesKeepTheScopeCurrent() throws
	{
		let directory = try makeTemporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let project = directory.appendingPathComponent(
			"checkout",
			isDirectory: true
		)
		try FileManager.default.createDirectory(
			at: project,
			withIntermediateDirectories: true
		)
		let scope = try #require(ProjectFileIndexWatchScope.capture(projectPath: project.path))
		try "sibling".write(
			to: directory.appendingPathComponent("unrelated.swift"),
			atomically: true,
			encoding: .utf8
		)
		#expect(scope.isCurrent)

		try FileManager.default.moveItem(
			at: project,
			to: directory.appendingPathComponent(
				"retired",
				isDirectory: true
			)
		)
		let absent = try #require(ProjectFileIndexWatchScope.capture(projectPath: project.path))
		#expect(absent.root == nil)
		#expect(absent.isCurrent)
		#expect(!scope.isCurrent)
		try FileManager.default.createDirectory(
			at: project,
			withIntermediateDirectories: true
		)
		#expect(!absent.isCurrent)
		#expect(!scope.isCurrent)
	}

	private func makeTemporaryDirectory() throws -> URL
	{
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
			"ProjectFileIndexWatchScope-\(UUID().uuidString)",
			isDirectory: true
		)
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)
		return directory
	}
}

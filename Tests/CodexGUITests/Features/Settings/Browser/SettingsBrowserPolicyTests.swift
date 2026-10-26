import Testing

@testable import CodexGUI

struct SettingsBrowserPolicyTests
{
	@Test
	func normalizesOriginsWithoutDroppingSecurityRelevantComponents()
	{
		#expect(SettingsBrowserPolicy.normalizedOrigin(" HTTPS://Example.COM:8443/ ")
			== "https://example.com:8443")
		#expect(SettingsBrowserPolicy.normalizedOrigin("http://localhost:3000")
			== "http://localhost:3000")
	}

	@Test(arguments: [
		"not a url",
		"ftp://example.com",
		"https://user:secret@example.com",
		"https://example.com/private",
		"https://example.com?token=secret",
		"https://example.com#private",
		"https://",
		"https://exam ple.com",
	])
	func rejectsValuesThatWouldSilentlyChangeTheRequestedSite(input: String)
	{
		#expect(SettingsBrowserPolicy.normalizedOrigin(input) == nil)
	}

	@Test
	func defaultEquivalentRulesDoNotEnableAdd()
	{
		#expect(!SettingsBrowserPolicy.hasChanges(
			[:],
			defaults: [:]
		))
		#expect(!SettingsBrowserPolicy.hasChanges(
			["access": "allow"],
			defaults: ["access": "allow"]
		))
		#expect(SettingsBrowserPolicy.hasChanges(
			["access": "deny"],
			defaults: ["access": "allow"]
		))
		#expect(SettingsBrowserPolicy.hasChanges(
			["uploads": "deny"],
			defaults: [:]
		))
	}
}

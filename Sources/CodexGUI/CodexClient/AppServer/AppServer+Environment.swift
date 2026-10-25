import Foundation

extension AppServer
{
	/// Keep caller configuration, while making relay warnings observable in the default setup.
	nonisolated static func subprocessEnvironment(_ inherited: [String: String]) -> [String: String]
	{
		var environment = inherited
		if environment["RUST_LOG"] == nil
		{
			environment["RUST_LOG"] =
				"error,codex_app_server_transport::transport::remote_control=info"
		}
		return environment
	}
}

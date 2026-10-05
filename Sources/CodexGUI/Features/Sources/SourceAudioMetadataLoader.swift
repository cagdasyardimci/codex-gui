import AVFoundation
import Foundation

/// Reads duration metadata from explicit local files without playing audio.
actor SourceAudioMetadataLoader
{
	private static let worker = SourceAudioMetadataLoader()

	/// The asset is shared only for asynchronous loading and thread-safe cancellation.
	private final class LoadingAsset: @unchecked Sendable
	{
		let asset: AVURLAsset

		init(url: URL)
		{
			asset = AVURLAsset(url: url)
		}
	}

	static func duration(path: String) async -> String?
	{
		await worker.loadDuration(path: path)
	}

	private func loadDuration(path: String) async -> String?
	{
		guard !Task.isCancelled, let url = LocalAttachmentURL.resolve(path),
				let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
				values.isRegularFile == true, FileManager.default.isReadableFile(atPath: url.path)
		else
		{
			return nil
		}
		let loading = LoadingAsset(url: url)
		return await withTaskCancellationHandler
		{
			guard !Task.isCancelled
			else
			{
				return nil
			}
			do
			{
				let duration = try await loading.asset.load(.duration)
				let seconds = duration.seconds
				guard !Task.isCancelled, seconds.isFinite, seconds >= 0,
						seconds < Double(Int.max)
				else
				{
					return nil
				}
				return Self.formattedDuration(Int(seconds.rounded(.down)))
			}
			catch
			{
				return nil
			}
		} onCancel:
		{
			loading.asset.cancelLoading()
		}
	}

	private static func formattedDuration(_ seconds: Int) -> String
	{
		let minutes = seconds / 60
		let remainder = padded(seconds % 60)
		if minutes >= 60
		{
			return "\(minutes / 60):\(padded(minutes % 60)):\(remainder)"
		}
		return "\(padded(minutes)):\(remainder)"
	}

	private static func padded(_ value: Int) -> String
	{
		value < 10 ? "0\(value)" : String(value)
	}
}

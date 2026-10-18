import Foundation
import zlib

func validatedPNGDimensions(_ data: Data) throws -> (Int, Int)
{
	try data.withUnsafeBytes
	{
		(bytes: UnsafeRawBufferPointer) in
		guard bytes.starts(with: [137, 80, 78, 71, 13, 10, 26, 10])
		else
		{
			throw EvidenceError.invalid("invalid PNG signature")
		}
		func uint(_ offset: Int) -> Int
		{
			bytes[offset ..< offset + 4].reduce(0)
			{
				$0 << 8 | Int($1)
			}
		}
		var offset = 8, width = 0, height = 0, ended = false, idat = Data()
		var depth = 0, color = 0, interlace = 0
		let depths = [0: [1, 2, 4, 8, 16], 2: [8, 16], 3: [1, 2, 4, 8], 4: [8, 16], 6: [8, 16]]
		while offset < bytes.count
		{
			guard bytes.count - offset >= 12
			else
			{
				throw EvidenceError.invalid("truncated PNG chunk")
			}
			let length = uint(offset), end = offset + 8 + length
			guard end <= bytes.count - 4
			else
			{
				throw EvidenceError.invalid("truncated PNG data")
			}
			let kind = String(
				decoding: bytes[offset + 4 ..< offset + 8],
				as: UTF8.self
			)
			let crc = crc32(
				0,
				bytes.bindMemory(to: Bytef.self).baseAddress!.advanced(by: offset + 4),
				uInt(length + 4)
			)
			guard crc == uint(end)
			else
			{
				throw EvidenceError.invalid("PNG chunk checksum mismatch")
			}
			if width == 0
			{
				guard kind == "IHDR",
						length == 13
				else
				{
					throw EvidenceError.invalid("missing PNG image header")
				}
				width = uint(offset + 8); height = uint(offset + 12)
				depth = Int(bytes[offset + 16]); color = Int(bytes[offset + 17]); interlace =
					Int(bytes[offset + 20])
				guard width > 0, height > 0, depths[color]?.contains(depth) == true,
						bytes[offset + 18] == 0, bytes[offset + 19] == 0,
						interlace <= 1
				else
				{
					throw EvidenceError.invalid("invalid PNG image header")
				}
			}
			else if kind == "IHDR"
			{
				throw EvidenceError.invalid("duplicate PNG image header")
			}
			if kind == "IDAT"
			{
				idat.append(contentsOf: bytes[offset + 8 ..< end])
			}
			if kind == "IEND"
			{
				guard length == 0,
						end + 4 == bytes.count
				else
				{
					throw EvidenceError.invalid("invalid PNG end")
				}
				ended = true; break
			}
			offset = end + 4
		}
		guard ended,
				!idat.isEmpty
		else
		{
			throw EvidenceError.invalid("PNG pixels or end chunk missing")
		}
		let channels = [0: 1, 2: 3, 3: 1, 4: 2, 6: 4][color]!
		let rowSize = (width * depth * channels + 7) / 8 + 1
		guard rowSize <= 256_000_000 / height
		else
		{
			throw EvidenceError.invalid("PNG pixel allocation exceeds evidence limit")
		}
		let pixelBytes = rowSize * height
		// Include interlaced per-pass row prefixes in the allocation budget.
		let passBytes = interlace == 1 ? height * 8 + 1024 : 0
		guard passBytes <= 256_000_000 - pixelBytes
		else
		{
			throw EvidenceError.invalid("PNG pixel allocation exceeds evidence limit")
		}
		var pixels = [UInt8](
			repeating: 0,
			count: pixelBytes + passBytes
		)
		var count = uLongf(pixels.count)
		let status = idat.withUnsafeBytes
		{
			data in pixels.withUnsafeMutableBytes
			{
				output in
				uncompress(
					output.bindMemory(to: Bytef.self).baseAddress,
					&count,
					data.bindMemory(to: Bytef.self).baseAddress,
					uLong(data.count)
				)
			}
		}
		guard status == Z_OK,
				count > 0
		else
		{
			throw EvidenceError.invalid("invalid compressed PNG pixels")
		}
		if interlace == 0
		{
			guard count == rowSize * height,
					stride(
					from: 0,
					to: Int(count),
					by: rowSize
					).allSatisfy(
					{
						pixels[$0] <= 4
					}
					)
			else
			{
				throw EvidenceError.invalid("invalid PNG pixel rows")
			}
		}
		return (width, height)
	}
}

import CoreFoundation
import Foundation

/// JSON-RPC request IDs retain their wire type so integer 13 and string "13" stay distinct.
enum JSONRPCRequestID: Hashable
{
	case integer(Int64)
	case string(String)

	init?(json: Any)
	{
		if let value = json as? String
		{
			self = .string(value)
			return
		}
		guard let number = json as? NSNumber,
				CFGetTypeID(number) != CFBooleanGetTypeID(),
				!["d", "f"].contains(String(cString: number.objCType)),
				let value = Int64(number.stringValue)
		else
		{
			return nil
		}
		self = .integer(value)
	}

	var key: String
	{
		switch self
		{
		case .integer(let value): "integer:\(value)"
		case .string(let value): "string:\(value)"
		}
	}

	var wireValue: Any
	{
		switch self
		{
		case .integer(let value): value
		case .string(let value): value
		}
	}
}

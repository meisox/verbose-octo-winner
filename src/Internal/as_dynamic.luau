--!strict

local Types = require("../Types")
local fixed = require("../Dynamic/fixed")

return function<T>(codec: Types.AnyCodec<T>): Types.DynamicCodec<T>
	local candidate = codec :: any
	if type(candidate) ~= "table" then error("Serdes expected a codec table") end
	if type(candidate.measure) == "function" then
		if type(candidate.unsafe_measure) ~= "function" or type(candidate.min_size) ~= "number" then
			error("Serdes dynamic codecs must provide checked measure, unsafe_measure, and min_size")
		end
		return candidate
	end
	return fixed(candidate)
end

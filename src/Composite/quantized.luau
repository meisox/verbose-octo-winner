--!strict
--!native

local Types = require("../Types")
local uint24 = require("../Internal/uint24")
local extreme = require("../Internal/quantized_extreme")

type Codec<T> = Types.Codec<T>

return function(minimum: number, maximum: number, bits: number): Codec<number>
	if type(minimum) ~= "number" or not math.isfinite(minimum) then
		error(`Serdes.quantized expected finite minimum, got {minimum}`)
	end

	if type(maximum) ~= "number" or not math.isfinite(maximum) then
		error(`Serdes.quantized expected finite maximum, got {maximum}`)
	end

	if minimum >= maximum then
		error(`Serdes.quantized expected minimum < maximum, got [{minimum}, {maximum}]`)
	end

	if type(bits) ~= "number" or bits % 1 ~= 0 or bits < 1 or bits > 32 then
		error(`Serdes.quantized expected integer bit count in [1, 32], got {bits}`)
	end

	local quantized_maximum = 2 ^ bits - 1
	local encode_scale = quantized_maximum / (maximum - minimum)
	local decode_scale = (maximum - minimum) / quantized_maximum

	if not math.isfinite(encode_scale) or not math.isfinite(decode_scale)
		or encode_scale < 2.2250738585072014e-308 or decode_scale < 2.2250738585072014e-308 then
		return extreme(minimum, maximum, bits)
	end

	local exact_endpoints = (minimum == 0 or math.abs(minimum) >= 2.2250738585072014e-308)
		and minimum + quantized_maximum * decode_scale == maximum

	local function validate(value: number): ()
		if type(value) ~= "number" then
			error(`Serdes.quantized expected number, got {typeof(value)}`)
		end

		if not math.isfinite(value) or value < minimum or value > maximum then
			error(`Serdes.quantized expected finite value in [{minimum}, {maximum}], got {value}`)
		end
	end

	local function unsafe_pack(value: number): number
		return math.round((value - minimum) * encode_scale)
	end

	local function pack(value: number): number
		if type(value) ~= "number" then
			error(`Serdes.quantized expected number, got {typeof(value)}`)
		end

		if not math.isfinite(value) or value < minimum or value > maximum then
			error(`Serdes.quantized expected finite value in [{minimum}, {maximum}], got {value}`)
		end

		return math.round((value - minimum) * encode_scale)
	end

	local function unpack(value: number): number
		if value == 0 then return minimum end
		if value == quantized_maximum then return maximum end
		if value > quantized_maximum then error(`Serdes.quantized decoded invalid value {value}`) end
		return math.clamp(minimum + value * decode_scale, minimum, maximum)
	end

	if bits <= 8 then
		local function unsafe_write(target: buffer, offset: number, value: number): ()
			buffer.writeu8(target, offset, math.round((value - minimum) * encode_scale))
		end

		local function write(target: buffer, offset: number, value: number): ()
			if type(value) ~= "number" then
				error(`Serdes.quantized expected number, got {typeof(value)}`)
			end

			if not math.isfinite(value) or value < minimum or value > maximum then
				error(`Serdes.quantized expected finite value in [{minimum}, {maximum}], got {value}`)
			end

			buffer.writeu8(target, offset, math.round((value - minimum) * encode_scale))
		end

		local unsafe_read: (buffer, number, number?) -> number
		if exact_endpoints then
			unsafe_read = function(source: buffer, offset: number, _output: number?): number
				return minimum + buffer.readu8(source, offset) * decode_scale
			end
		else
			unsafe_read = function(source: buffer, offset: number, _output: number?): number
				return unpack(buffer.readu8(source, offset))
			end
		end
		local read = unsafe_read
		if bits ~= 8 then
			read = function(source: buffer, offset: number, _output: number?): number
				local encoded = buffer.readu8(source, offset)
				if encoded > quantized_maximum then error(`Serdes.quantized decoded invalid value {encoded}`) end
				return if exact_endpoints then minimum + encoded * decode_scale else unpack(encoded)
			end
		end

		return table.freeze({
			size = 1,
			delta_safe = true, wire_equal = function(a: number, b: number): boolean return unsafe_pack(a) == unsafe_pack(b) end,

			validate = validate,
			unsafe_write = unsafe_write,
			write = write,
			unsafe_write_fresh = unsafe_write,
			write_fresh = write,
			read = read,
			unsafe_read = unsafe_read,

			bits = bits,
			unsafe_pack = unsafe_pack,
			pack = pack,
			unpack = unpack,
			unsafe_unpack = unpack,
		})
	elseif bits <= 16 then
		local function unsafe_write(target: buffer, offset: number, value: number): ()
			buffer.writeu16(target, offset, math.round((value - minimum) * encode_scale))
		end

		local function write(target: buffer, offset: number, value: number): ()
			if type(value) ~= "number" then
				error(`Serdes.quantized expected number, got {typeof(value)}`)
			end

			if not math.isfinite(value) or value < minimum or value > maximum then
				error(`Serdes.quantized expected finite value in [{minimum}, {maximum}], got {value}`)
			end

			buffer.writeu16(target, offset, math.round((value - minimum) * encode_scale))
		end

		local unsafe_read: (buffer, number, number?) -> number
		if exact_endpoints then
			unsafe_read = function(source: buffer, offset: number, _output: number?): number
				return minimum + buffer.readu16(source, offset) * decode_scale
			end
		else
			unsafe_read = function(source: buffer, offset: number, _output: number?): number
				return unpack(buffer.readu16(source, offset))
			end
		end
		local read = unsafe_read
		if bits ~= 16 then
			read = function(source: buffer, offset: number, _output: number?): number
				local encoded = buffer.readu16(source, offset)
				if encoded > quantized_maximum then error(`Serdes.quantized decoded invalid value {encoded}`) end
				return if exact_endpoints then minimum + encoded * decode_scale else unpack(encoded)
			end
		end

		return table.freeze({
			size = 2,
			delta_safe = true, wire_equal = function(a: number, b: number): boolean return unsafe_pack(a) == unsafe_pack(b) end,

			validate = validate,
			unsafe_write = unsafe_write,
			write = write,
			unsafe_write_fresh = unsafe_write,
			write_fresh = write,
			read = read,
			unsafe_read = unsafe_read,

			bits = bits,
			unsafe_pack = unsafe_pack,
			pack = pack,
			unpack = unpack,
			unsafe_unpack = unpack,
		})
	elseif bits <= 24 then
		local function unsafe_write(target: buffer, offset: number, value: number): ()
			uint24.write(target, offset, math.round((value - minimum) * encode_scale))
		end

		local function write(target: buffer, offset: number, value: number): ()
			if type(value) ~= "number" then
				error(`Serdes.quantized expected number, got {typeof(value)}`)
			end

			if not math.isfinite(value) or value < minimum or value > maximum then
				error(`Serdes.quantized expected finite value in [{minimum}, {maximum}], got {value}`)
			end

			uint24.write(target, offset, math.round((value - minimum) * encode_scale))
		end

		local unsafe_read: (buffer, number, number?) -> number
		if exact_endpoints then
			unsafe_read = function(source: buffer, offset: number, _output: number?): number
				return minimum + uint24.read(source, offset) * decode_scale
			end
		else
			unsafe_read = function(source: buffer, offset: number, _output: number?): number
				return unpack(uint24.read(source, offset))
			end
		end
		local read = unsafe_read
		if bits ~= 24 then
			read = function(source: buffer, offset: number, _output: number?): number
				local encoded = uint24.read(source, offset)
				if encoded > quantized_maximum then error(`Serdes.quantized decoded invalid value {encoded}`) end
				return if exact_endpoints then minimum + encoded * decode_scale else unpack(encoded)
			end
		end

		return table.freeze({
			size = 3,
			delta_safe = true, wire_equal = function(a: number, b: number): boolean return unsafe_pack(a) == unsafe_pack(b) end,

			validate = validate,
			unsafe_write = unsafe_write,
			write = write,
			unsafe_write_fresh = unsafe_write,
			write_fresh = write,
			read = read,
			unsafe_read = unsafe_read,

			bits = bits,
			unsafe_pack = unsafe_pack,
			pack = pack,
			unpack = unpack,
			unsafe_unpack = unpack,
		})	else
		local function unsafe_write(target: buffer, offset: number, value: number): ()
			buffer.writeu32(target, offset, math.round((value - minimum) * encode_scale))
		end

		local function write(target: buffer, offset: number, value: number): ()
			if type(value) ~= "number" then
				error(`Serdes.quantized expected number, got {typeof(value)}`)
			end

			if not math.isfinite(value) or value < minimum or value > maximum then
				error(`Serdes.quantized expected finite value in [{minimum}, {maximum}], got {value}`)
			end

			buffer.writeu32(target, offset, math.round((value - minimum) * encode_scale))
		end

		local unsafe_read: (buffer, number, number?) -> number
		if exact_endpoints then
			unsafe_read = function(source: buffer, offset: number, _output: number?): number
				return minimum + buffer.readu32(source, offset) * decode_scale
			end
		else
			unsafe_read = function(source: buffer, offset: number, _output: number?): number
				return unpack(buffer.readu32(source, offset))
			end
		end
		local read = unsafe_read
		if bits ~= 32 then
			read = function(source: buffer, offset: number, _output: number?): number
				local encoded = buffer.readu32(source, offset)
				if encoded > quantized_maximum then error(`Serdes.quantized decoded invalid value {encoded}`) end
				return if exact_endpoints then minimum + encoded * decode_scale else unpack(encoded)
			end
		end

		return table.freeze({
			size = 4,
			delta_safe = true, wire_equal = function(a: number, b: number): boolean return unsafe_pack(a) == unsafe_pack(b) end,

			validate = validate,
			unsafe_write = unsafe_write,
			write = write,
			unsafe_write_fresh = unsafe_write,
			write_fresh = write,
			read = read,
			unsafe_read = unsafe_read,

			bits = bits,
			unsafe_pack = unsafe_pack,
			pack = pack,
			unpack = unpack,
			unsafe_unpack = unpack,
		})
	end
end

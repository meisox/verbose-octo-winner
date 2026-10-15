--!strict
--!native

local Types = require("../Types")
local uint24 = require("../Internal/uint24")
local required_bits = require("../Internal/bits")

type Codec<T> = Types.Codec<T>

local MAX_U32 = 4_294_967_295
local MAX_EXACT_INTEGER = 9_007_199_254_740_991

return function(minimum: number, maximum: number): Codec<number>
	if
		type(minimum) ~= "number"
		or not math.isfinite(minimum)
		or minimum % 1 ~= 0
		or math.abs(minimum) > MAX_EXACT_INTEGER
	then
		error(`Serdes.range expected an exact integer minimum, got {minimum}`)
	end

	if
		type(maximum) ~= "number"
		or not math.isfinite(maximum)
		or maximum % 1 ~= 0
		or math.abs(maximum) > MAX_EXACT_INTEGER
	then
		error(`Serdes.range expected an exact integer maximum, got {maximum}`)
	end

	if minimum > maximum then
		error(`Serdes.range expected minimum <= maximum, got [{minimum}, {maximum}]`)
	end

	local span = maximum - minimum

	if span > MAX_U32 then
		error(`Serdes.range span cannot exceed {MAX_U32}, got {span}`)
	end

	local bits = required_bits(span)

	local function validate(value: number): ()
		if type(value) ~= "number" then
			error(`Serdes.range expected number, got {typeof(value)}`)
		end

		if value % 1 ~= 0 or value < minimum or value > maximum then
			error(`Serdes.range expected integer in [{minimum}, {maximum}], got {value}`)
		end
	end

	local function unsafe_pack(value: number): number
		return value - minimum
	end

	local function pack(value: number): number
		if type(value) ~= "number" then
			error(`Serdes.range expected number, got {typeof(value)}`)
		end

		if value % 1 ~= 0 or value < minimum or value > maximum then
			error(`Serdes.range expected integer in [{minimum}, {maximum}], got {value}`)
		end

		return value - minimum
	end

	local function unpack(value: number): number
		if value > span then
			error(`Serdes.range decoded invalid value {value}`)
		end

		return value + minimum
	end

	local function unsafe_unpack(value: number): number
		return value + minimum
	end

	if span == 0 then
		local function unsafe_write(_target: buffer, _offset: number, _value: number): () end

		local function write(_target: buffer, _offset: number, value: number): ()
			if type(value) ~= "number" then
				error(`Serdes.range expected number, got {typeof(value)}`)
			end

			if value ~= minimum then
				error(`Serdes.range expected integer in [{minimum}, {maximum}], got {value}`)
			end
		end

		local function read(_source: buffer, _offset: number, _output: number?): number
			return minimum
		end

		return table.freeze({
			size = 0,
			delta_safe = true, key_safe = true,

			validate = validate,
			unsafe_write = unsafe_write,
			write = write,
			unsafe_write_fresh = unsafe_write,
			write_fresh = write,
			read = read,
			unsafe_read = read,

			bits = bits,
			unsafe_pack = unsafe_pack,
			pack = pack,
			unpack = unpack,
			unsafe_unpack = unsafe_unpack,
		})
	elseif span <= 255 then
		local function unsafe_write(target: buffer, offset: number, value: number): ()
			buffer.writeu8(target, offset, value - minimum)
		end

		local function write(target: buffer, offset: number, value: number): ()
			if type(value) ~= "number" then
				error(`Serdes.range expected number, got {typeof(value)}`)
			end

			if value % 1 ~= 0 or value < minimum or value > maximum then
				error(`Serdes.range expected integer in [{minimum}, {maximum}], got {value}`)
			end

			buffer.writeu8(target, offset, value - minimum)
		end

		local function read(source: buffer, offset: number, _output: number?): number
			local encoded = buffer.readu8(source, offset)

			if encoded > span then
				error(`Serdes.range decoded invalid value {encoded}`)
			end

			return encoded + minimum
		end

		local function unsafe_read(source: buffer, offset: number, _output: number?): number
			return buffer.readu8(source, offset) + minimum
		end

		return table.freeze({
			size = 1,
			delta_safe = true, key_safe = true,

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
			unsafe_unpack = unsafe_unpack,
		})
	elseif span <= 65_535 then
		local function unsafe_write(target: buffer, offset: number, value: number): ()
			buffer.writeu16(target, offset, value - minimum)
		end

		local function write(target: buffer, offset: number, value: number): ()
			if type(value) ~= "number" then
				error(`Serdes.range expected number, got {typeof(value)}`)
			end

			if value % 1 ~= 0 or value < minimum or value > maximum then
				error(`Serdes.range expected integer in [{minimum}, {maximum}], got {value}`)
			end

			buffer.writeu16(target, offset, value - minimum)
		end

		local function read(source: buffer, offset: number, _output: number?): number
			local encoded = buffer.readu16(source, offset)

			if encoded > span then
				error(`Serdes.range decoded invalid value {encoded}`)
			end

			return encoded + minimum
		end

		local function unsafe_read(source: buffer, offset: number, _output: number?): number
			return buffer.readu16(source, offset) + minimum
		end

		return table.freeze({
			size = 2,
			delta_safe = true, key_safe = true,

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
			unsafe_unpack = unsafe_unpack,
		})
	elseif span <= 16_777_215 then
		local function unsafe_write(target: buffer, offset: number, value: number): ()
			uint24.write(target, offset, value - minimum)
		end

		local function write(target: buffer, offset: number, value: number): ()
			if type(value) ~= "number" then
				error(`Serdes.range expected number, got {typeof(value)}`)
			end

			if value % 1 ~= 0 or value < minimum or value > maximum then
				error(`Serdes.range expected integer in [{minimum}, {maximum}], got {value}`)
			end

			uint24.write(target, offset, value - minimum)
		end

		local function read(source: buffer, offset: number, _output: number?): number
			local encoded = uint24.read(source, offset)

			if encoded > span then
				error(`Serdes.range decoded invalid value {encoded}`)
			end

			return encoded + minimum
		end

		local function unsafe_read(source: buffer, offset: number, _output: number?): number
			return uint24.read(source, offset) + minimum
		end

		return table.freeze({
			size = 3,
			delta_safe = true, key_safe = true,

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
			unsafe_unpack = unsafe_unpack,
		})	else
		local function unsafe_write(target: buffer, offset: number, value: number): ()
			buffer.writeu32(target, offset, value - minimum)
		end

		local function write(target: buffer, offset: number, value: number): ()
			if type(value) ~= "number" then
				error(`Serdes.range expected number, got {typeof(value)}`)
			end

			if value % 1 ~= 0 or value < minimum or value > maximum then
				error(`Serdes.range expected integer in [{minimum}, {maximum}], got {value}`)
			end

			buffer.writeu32(target, offset, value - minimum)
		end

		local function read(source: buffer, offset: number, _output: number?): number
			local encoded = buffer.readu32(source, offset)

			if encoded > span then
				error(`Serdes.range decoded invalid value {encoded}`)
			end

			return encoded + minimum
		end

		local function unsafe_read(source: buffer, offset: number, _output: number?): number
			return buffer.readu32(source, offset) + minimum
		end

		return table.freeze({
			size = 4,
			delta_safe = true, key_safe = true,

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
			unsafe_unpack = unsafe_unpack,
		})
	end
end

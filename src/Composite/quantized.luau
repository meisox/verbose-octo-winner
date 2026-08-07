--!strict
--!native

local Types = require("../Types")

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

	if bits ~= 8 and bits ~= 16 and bits ~= 32 then
		error(`Serdes.quantized expected 8, 16, or 32 bits, got {bits}`)
	end

	local quantized_maximum = if bits == 8 then 255 elseif bits == 16 then 65_535 else 4_294_967_295
	local encode_scale = quantized_maximum / (maximum - minimum)
	local decode_scale = (maximum - minimum) / quantized_maximum

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
		return minimum + value * decode_scale
	end

	if bits == 8 then
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

		local function read(source: buffer, offset: number, _output: number?): number
			return minimum + buffer.readu8(source, offset) * decode_scale
		end

		return table.freeze({
			size = 1,
			delta_safe = true,

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
			unsafe_unpack = unpack,
		})
	elseif bits == 16 then
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

		local function read(source: buffer, offset: number, _output: number?): number
			return minimum + buffer.readu16(source, offset) * decode_scale
		end

		return table.freeze({
			size = 2,
			delta_safe = true,

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
			unsafe_unpack = unpack,
		})
	else
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

		local function read(source: buffer, offset: number, _output: number?): number
			return minimum + buffer.readu32(source, offset) * decode_scale
		end

		return table.freeze({
			size = 4,
			delta_safe = true,

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
			unsafe_unpack = unpack,
		})
	end
end

--!strict
--!native

-- Rare ranges whose scale overflows or underflows use normalized arithmetic.
-- Ordinary ranges retain the specialized multiply-only writers.
local Types = require("../Types")

return function(minimum: number, maximum: number, bits: number): Types.Codec<number>
	local limit = 2 ^ bits - 1
	local size = math.ceil(bits / 8)
	local span = maximum - minimum
	local pack_value: (number) -> number
	local unpack_value: (number) -> number

	if span < 1e-280 then
		-- Some engine arithmetic paths flush subnormal results to zero. Work
		-- in an exactly power-of-two scaled interval; construct subnormal
		-- outputs from their IEEE-754 mantissa instead of arithmetic on them.
		local scale = 2 ^ 1022
		local scaled_minimum = minimum * scale
		local scaled_span = maximum * scale - scaled_minimum
		local scratch = buffer.create(8)
		pack_value = function(value: number): number
			return math.round(((value * scale - scaled_minimum) / scaled_span) * limit)
		end
		unpack_value = function(value: number): number
			local scaled = scaled_minimum + scaled_span * (value / limit)
			if math.abs(scaled) >= 1 then return math.clamp(scaled / scale, minimum, maximum) end
			local mantissa = math.round(math.abs(scaled) * 4_503_599_627_370_496)
			buffer.writeu32(scratch, 0, mantissa % 4_294_967_296)
			buffer.writeu32(scratch, 4, math.floor(mantissa / 4_294_967_296) + (if scaled < 0 then 2_147_483_648 else 0))
			return buffer.readf64(scratch, 0)
		end
	elseif math.isfinite(span) then
		pack_value = function(value: number): number
			return math.round(((value - minimum) / span) * limit)
		end
		unpack_value = function(value: number): number
			return math.clamp(minimum + span * (value / limit), minimum, maximum)
		end
	else
		local half_minimum = minimum * 0.5
		local half_span = maximum * 0.5 - half_minimum
		pack_value = function(value: number): number
			return math.round(((value * 0.5 - half_minimum) / half_span) * limit)
		end
		unpack_value = function(value: number): number
			local fraction = value / limit
			return math.clamp((1 - fraction) * minimum + fraction * maximum, minimum, maximum)
		end
	end

	local function validate(value: number): ()
		if type(value) ~= "number" or not math.isfinite(value) or value < minimum or value > maximum then
			error(`Serdes.quantized expected finite value in [{minimum}, {maximum}], got {value}`)
		end
	end
	local function pack(value: number): number
		validate(value)
		return pack_value(value)
	end
	local function unpack(value: number): number
		if value == 0 then return minimum end
		if value == limit then return maximum end
		if value > limit then error(`Serdes.quantized decoded invalid value {value}`) end
		return unpack_value(value)
	end
	local function unsafe_write(target: buffer, offset: number, value: number): ()
		buffer.writebits(target, offset * 8, size * 8, pack_value(value))
	end
	local function write(target: buffer, offset: number, value: number): ()
		buffer.writebits(target, offset * 8, size * 8, pack(value))
	end
	local function read(source: buffer, offset: number, _output: number?): number
		return unpack(buffer.readbits(source, offset * 8, size * 8))
	end
	local function unsafe_read(source: buffer, offset: number, _output: number?): number
		return unpack_value(buffer.readbits(source, offset * 8, size * 8))
	end
	return table.freeze({
		size = size, bits = bits, delta_safe = true,
		wire_equal = function(a: number, b: number): boolean return pack_value(a) == pack_value(b) end,
		validate = validate, pack = pack, unsafe_pack = pack_value,
		unpack = unpack, unsafe_unpack = unpack_value,
		write = write, unsafe_write = unsafe_write,
		write_fresh = write, unsafe_write_fresh = unsafe_write,
		read = read, unsafe_read = unsafe_read,
	})
end

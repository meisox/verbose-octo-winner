--!strict
--!native

local Types = require("../Types")
local quantization = require("../Internal/signed_quantization")
type Result = Types.Codec<Vector2> & {read max_abs: Vector2, read step: Vector2, read max_error: Vector2}

return function(max_abs: number | Vector2, bits: number): Result
	local extent: Vector2
	if type(max_abs) == "number" then
		extent = Vector2.new(max_abs, max_abs)
	elseif typeof(max_abs) == "Vector2" then
		extent = max_abs :: Vector2
	else
		error("Serdes.quantized_vector2 expected a number or Vector2 extent")
	end
	local encode_x, step_x, error_x = quantization(extent.X, bits)
	local encode_y, step_y, error_y = quantization(extent.Y, bits)
	local size = math.ceil(bits * 2 / 8)
	local padding = size * 8 - bits * 2
	local sign, modulus = 2 ^ (bits - 1), 2 ^ bits
	local function validate(value: Vector2): ()
		if typeof(value) ~= "Vector2" then error("Serdes.quantized_vector2 expected Vector2") end
		if not math.isfinite(value.X) or math.abs(value.X) > extent.X
			or not math.isfinite(value.Y) or math.abs(value.Y) > extent.Y then
			error("Serdes.quantized_vector2 component is outside the configured extent")
		end
	end
	local function unsafe_write(target: buffer, offset: number, value: Vector2): ()
		local start = offset * 8
		local x = math.round(value.X * encode_x)
		buffer.writebits(target, start + 0 * bits, bits, if x < 0 then x + modulus else x)
		local y = math.round(value.Y * encode_y)
		buffer.writebits(target, start + 1 * bits, bits, if y < 0 then y + modulus else y)
		if padding > 0 then buffer.writebits(target, start + 2 * bits, padding, 0) end
	end
	local function write(target: buffer, offset: number, value: Vector2): ()
		validate(value)
		unsafe_write(target, offset, value)
	end
	local function compile_reader(checked: boolean)
		return function(source: buffer, offset: number, _output: Vector2?): Vector2
			local start = offset * 8
			local x = buffer.readbits(source, start + 0 * bits, bits)
			if x >= sign then x -= modulus end
			local y = buffer.readbits(source, start + 1 * bits, bits)
			if y >= sign then y -= modulus end
			if checked then
				if x == -sign or y == -sign then error("Serdes.quantized_vector2 reserved signed code") end
				if padding > 0 and buffer.readbits(source, start + 2 * bits, padding) ~= 0 then error("Serdes.quantized_vector2 nonzero padding") end
			end
			return Vector2.new(x * step_x, y * step_y)
		end
	end
	local function wire_equal(a: Vector2, b: Vector2): boolean
		return math.round(a.X * encode_x) == math.round(b.X * encode_x)
			and math.round(a.Y * encode_y) == math.round(b.Y * encode_y)
	end
	return table.freeze({
		size = size, delta_safe = true, wire_equal = wire_equal,
		max_abs = extent,
		step = Vector2.new(step_x, step_y),
		max_error = Vector2.new(error_x, error_y),
		validate = validate, write = write, unsafe_write = unsafe_write,
		write_fresh = write, unsafe_write_fresh = unsafe_write,
		read = compile_reader(true), unsafe_read = compile_reader(false),
	})
end

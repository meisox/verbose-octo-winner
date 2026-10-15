--!strict
--!native

local Types = require("../Types")
local quantization = require("../Internal/signed_quantization")
type Result = Types.Codec<Vector3> & {read max_abs: Vector3, read step: Vector3, read max_error: Vector3}

return function(max_abs: number | Vector3, bits: number): Result
	local extent: Vector3
	if type(max_abs) == "number" then
		extent = Vector3.new(max_abs, max_abs, max_abs)
	elseif typeof(max_abs) == "Vector3" then
		extent = max_abs :: Vector3
	else
		error("Serdes.quantized_vector3 expected a number or Vector3 extent")
	end
	local encode_x, step_x, error_x = quantization(extent.X, bits)
	local encode_y, step_y, error_y = quantization(extent.Y, bits)
	local encode_z, step_z, error_z = quantization(extent.Z, bits)
	local size = math.ceil(bits * 3 / 8)
	local padding = size * 8 - bits * 3
	local sign, modulus = 2 ^ (bits - 1), 2 ^ bits
	local function validate(value: Vector3): ()
		if typeof(value) ~= "Vector3" then error("Serdes.quantized_vector3 expected Vector3") end
		if not math.isfinite(value.X) or math.abs(value.X) > extent.X
			or not math.isfinite(value.Y) or math.abs(value.Y) > extent.Y
			or not math.isfinite(value.Z) or math.abs(value.Z) > extent.Z then
			error("Serdes.quantized_vector3 component is outside the configured extent")
		end
	end
	local function unsafe_write(target: buffer, offset: number, value: Vector3): ()
		local start = offset * 8
		local x = math.round(value.X * encode_x)
		buffer.writebits(target, start + 0 * bits, bits, if x < 0 then x + modulus else x)
		local y = math.round(value.Y * encode_y)
		buffer.writebits(target, start + 1 * bits, bits, if y < 0 then y + modulus else y)
		local z = math.round(value.Z * encode_z)
		buffer.writebits(target, start + 2 * bits, bits, if z < 0 then z + modulus else z)
		if padding > 0 then buffer.writebits(target, start + 3 * bits, padding, 0) end
	end
	local function write(target: buffer, offset: number, value: Vector3): ()
		validate(value)
		unsafe_write(target, offset, value)
	end
	local function compile_reader(checked: boolean)
		return function(source: buffer, offset: number, _output: Vector3?): Vector3
			local start = offset * 8
			local x = buffer.readbits(source, start + 0 * bits, bits)
			if x >= sign then x -= modulus end
			local y = buffer.readbits(source, start + 1 * bits, bits)
			if y >= sign then y -= modulus end
			local z = buffer.readbits(source, start + 2 * bits, bits)
			if z >= sign then z -= modulus end
			if checked then
				if x == -sign or y == -sign or z == -sign then error("Serdes.quantized_vector3 reserved signed code") end
				if padding > 0 and buffer.readbits(source, start + 3 * bits, padding) ~= 0 then error("Serdes.quantized_vector3 nonzero padding") end
			end
			return Vector3.new(x * step_x, y * step_y, z * step_z)
		end
	end
	local function wire_equal(a: Vector3, b: Vector3): boolean
		return math.round(a.X * encode_x) == math.round(b.X * encode_x)
			and math.round(a.Y * encode_y) == math.round(b.Y * encode_y)
			and math.round(a.Z * encode_z) == math.round(b.Z * encode_z)
	end
	return table.freeze({
		size = size, delta_safe = true, wire_equal = wire_equal,
		max_abs = extent,
		step = Vector3.new(step_x, step_y, step_z),
		max_error = Vector3.new(error_x, error_y, error_z),
		validate = validate, write = write, unsafe_write = unsafe_write,
		write_fresh = write, unsafe_write_fresh = unsafe_write,
		read = compile_reader(true), unsafe_read = compile_reader(false),
	})
end

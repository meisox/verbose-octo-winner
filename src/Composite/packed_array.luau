--!strict
--!native

local Types = require("../Types")
local sequence = require("../Internal/sequence")

return function<T>(element: Types.Codec<T>, count: number): Types.Codec<{T}>
	if type(count) ~= "number" or count % 1 ~= 0 or count < 0 or count > 1_073_741_824 then
		error(`Serdes.packed_array expected a non-negative integer count, got {count}`)
	end
	local width = element.bits
	local pack, unsafe_pack = element.pack, element.unsafe_pack
	local unpack, unsafe_unpack = element.unpack, element.unsafe_unpack
	if type(width) ~= "number" or width % 1 ~= 0 or width < 0 or width > 32
		or type(pack) ~= "function" or type(unsafe_pack) ~= "function"
		or type(unpack) ~= "function" or type(unsafe_unpack) ~= "function" then
		error("Serdes.packed_array expected a packable element codec")
	end
	local total_bits = width * count
	local size = math.ceil(total_bits / 8)
	if size > 1_073_741_824 then error("Serdes.packed_array encoded size exceeds the maximum buffer size") end
	local padding = size * 8 - total_bits
	local validate_sequence = sequence(count, false, "packed_array")
	local function validate(value: {T}): ()
		validate_sequence(value)
		for index = 1, count do pack(value[index]) end
	end
	local function compile_writer(packer: (T) -> number, checked: boolean)
		return function(target: buffer, offset: number, value: {T}): ()
			if checked then validate_sequence(value) end
			local position = offset * 8
			for index = 1, count do
				local encoded = packer(value[index])
				if width > 0 then buffer.writebits(target, position, width, encoded) end
				position += width
			end
			if padding > 0 then buffer.writebits(target, position, padding, 0) end
		end
	end
	local function compile_reader(unpacker: (number) -> T, checked: boolean)
		return function(source: buffer, offset: number, output: {T}?): {T}
			local result: {T} = if output == nil then table.create(count) else output
			local position = offset * 8
			if checked and padding > 0 and buffer.readbits(source, position + total_bits, padding) ~= 0 then
				error("Serdes.packed_array decoded nonzero padding bits")
			end
			for index = 1, count do
				result[index] = unpacker(if width == 0 then 0 else buffer.readbits(source, position, width))
				position += width
			end
			for index = #result, count + 1, -1 do result[index] = nil :: any end
			return result
		end
	end
	local write = compile_writer(pack, true)
	local unsafe_write = compile_writer(unsafe_pack, false)
	return table.freeze({
		size = size, validate = validate,
		write = write, unsafe_write = unsafe_write,
		write_fresh = write, unsafe_write_fresh = unsafe_write,
		read = compile_reader(unpack, true), unsafe_read = compile_reader(unsafe_unpack, false),
	})
end

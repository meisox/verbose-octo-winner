--!strict
--!native

local Types = require("../Types")
local as_dynamic = require("../Internal/as_dynamic")
local check_size = require("../Internal/size")

return function<T>(child: Types.AnyCodec<T>): Types.DynamicCodec<T?>
	local element = as_dynamic(child)
	local child_equal = element.wire_equal
	local wire_equal: ((T?, T?) -> boolean)? = nil
	if child_equal then
		wire_equal = function(a: T?, b: T?): boolean
			return if a == nil or b == nil then a == b else child_equal(a, b)
		end
	end
	local function measure(value: T?): number
		return if value == nil then 1 else check_size(1 + element.measure(value))
	end
	local function unsafe_measure(value: T?): number
		return if value == nil then 1 else 1 + element.unsafe_measure(value)
	end
	local function compile_writer(writer: (buffer, number, T) -> number)
		return function(target: buffer, offset: number, value: T?): number
			buffer.writeu8(target, offset, if value == nil then 0 else 1)
			return if value == nil then offset + 1 else writer(target, offset + 1, value)
		end
	end
	local function read(source: buffer, offset: number, output: T?): (T?, number)
		local marker = buffer.readu8(source, offset)
		if marker == 0 then return nil, offset + 1 end
		if marker ~= 1 then error(`Serdes.dynamic.optional decoded invalid presence byte {marker}`) end
		return element.read(source, offset + 1, output)
	end
	local function unsafe_read(source: buffer, offset: number, output: T?): (T?, number)
		if buffer.readu8(source, offset) == 0 then return nil, offset + 1 end
		return element.unsafe_read(source, offset + 1, output)
	end
	return table.freeze({
		measure = measure, unsafe_measure = unsafe_measure,
		min_size = 1, max_size = if element.max_size then math.min(1_073_741_824, 1 + element.max_size) else nil,
		fixed_size = if element.fixed_size == 0 then 1 else nil,
		nullable = true, value_like = element.value_like,
		key_safe = element.key_safe, key_less = element.key_less :: any,
		wire_equal = wire_equal,
		write = compile_writer(element.write), unsafe_write = compile_writer(element.unsafe_write),
		unsafe_write_fresh = compile_writer(element.unsafe_write_fresh or element.unsafe_write),
		read = read, unsafe_read = unsafe_read,
	})
end

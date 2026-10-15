--!strict
--!native

local Types = require("../Types")
local check_bounds = require("../Internal/bounds")
local check_size = require("../Internal/size")

type Codec<T> = Types.Codec<T>
type DynamicCodec<T> = Types.DynamicCodec<T>

return function<T>(codec: Codec<T>): DynamicCodec<T>
	local size = check_size(codec.size)
	local child_unsafe_write = codec.unsafe_write
	local child_write = codec.write
	local child_read = codec.read
	local child_unsafe_read = codec.unsafe_read
	local child_validate = codec.validate

	local function unsafe_measure(_value: T): number
		return size
	end
	local function measure(value: T): number
		child_validate(value)
		return size
	end

	local function unsafe_write(target: buffer, offset: number, value: T): number
		child_unsafe_write(target, offset, value)
		return offset + size
	end
	local function unsafe_write_fresh(target: buffer, offset: number, value: T): number
		codec.unsafe_write_fresh(target, offset, value)
		return offset + size
	end

	local function write(target: buffer, offset: number, value: T): number
		check_bounds(target, offset, size)
		child_write(target, offset, value)
		return offset + size
	end

	local function read(source: buffer, offset: number, output: T?): (T, number)
		check_bounds(source, offset, size)
		return child_read(source, offset, output), offset + size
	end

	local function unsafe_read(source: buffer, offset: number, output: T?): (T, number)
		return child_unsafe_read(source, offset, output), offset + size
	end

	return table.freeze({
		measure = measure,
		unsafe_measure = unsafe_measure,
		min_size = size, max_size = size, fixed_size = size, fixed_codec = codec,
		nullable = codec.nullable,
		key_safe = codec.key_safe, key_less = codec.key_less,
		wire_equal = codec.wire_equal,
		unsafe_write = unsafe_write,
		unsafe_write_fresh = unsafe_write_fresh,
		write = write,
		read = read,
		unsafe_read = unsafe_read,
		value_like = codec.delta_safe == true,
	})
end

--!strict
--!native

local Types = require("../Types")

type Codec<T> = Types.Codec<T>
type DynamicCodec<T> = Types.DynamicCodec<T>

return function<T>(codec: Codec<T>): DynamicCodec<T>
	local size = codec.size
	local child_unsafe_write = codec.unsafe_write_fresh
	local child_write = codec.write_fresh
	local child_read = codec.read
	local child_unsafe_read = codec.unsafe_read

	local function measure(_value: T): number
		return size
	end

	local function unsafe_write(target: buffer, offset: number, value: T): number
		child_unsafe_write(target, offset, value)
		return offset + size
	end

	local function write(target: buffer, offset: number, value: T): number
		child_write(target, offset, value)
		return offset + size
	end

	local function read(source: buffer, offset: number, output: T?): (T, number)
		return child_read(source, offset, output), offset + size
	end

	local function unsafe_read(source: buffer, offset: number, output: T?): (T, number)
		return child_unsafe_read(source, offset, output), offset + size
	end

	return table.freeze({
		measure = measure,
		unsafe_write = unsafe_write,
		write = write,
		read = read,
		unsafe_read = unsafe_read,
		value_like = codec.delta_safe == true,
	})
end

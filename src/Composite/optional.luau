--!strict
--!native

local Types = require("../Types")

type Codec<T> = Types.Codec<T>

return function<T>(codec: Codec<T>): Codec<T?>
	local payload_size = codec.size

	if not math.isfinite(payload_size) or payload_size % 1 ~= 0 or payload_size < 0 then
		error(`Serdes.optional received codec with invalid size {payload_size}`)
	end

	local SIZE = payload_size + 1

	if not math.isfinite(SIZE) or SIZE > 1_073_741_824 then
		error("Serdes.optional encoded size overflowed")
	end

	local child_validate = codec.validate
	local child_unsafe_write = codec.unsafe_write
	local child_write = codec.write
	local child_unsafe_write_fresh = codec.unsafe_write_fresh
	local child_write_fresh = codec.write_fresh
	local child_read = codec.read
	local child_unsafe_read = codec.unsafe_read
	local child_equal = codec.wire_equal
	local wire_equal: ((T?, T?) -> boolean)? = nil
	if child_equal then
		wire_equal = function(a: T?, b: T?): boolean
			return if a == nil or b == nil then a == b else child_equal(a, b)
		end
	end

	local function validate(value: T?): ()
		if value ~= nil then
			child_validate(value)
		end
	end

	local function unsafe_write(target: buffer, offset: number, value: T?): ()
		local payload_offset = offset + 1

		if value == nil then
			buffer.writeu8(target, offset, 0)

			if payload_size > 0 then
				buffer.fill(target, payload_offset, 0, payload_size)
			end

			return
		end

		buffer.writeu8(target, offset, 1)
		child_unsafe_write(target, payload_offset, value)
	end

	local function write(target: buffer, offset: number, value: T?): ()
		local payload_offset = offset + 1

		if value == nil then
			buffer.writeu8(target, offset, 0)

			if payload_size > 0 then
				buffer.fill(target, payload_offset, 0, payload_size)
			end

			return
		end

		buffer.writeu8(target, offset, 1)
		child_write(target, payload_offset, value)
	end

	local function unsafe_write_fresh(target: buffer, offset: number, value: T?): ()
		if value == nil then
			buffer.writeu8(target, offset, 0)
			return
		end

		buffer.writeu8(target, offset, 1)
		child_unsafe_write_fresh(target, offset + 1, value)
	end

	local function write_fresh(target: buffer, offset: number, value: T?): ()
		if value == nil then
			buffer.writeu8(target, offset, 0)
			return
		end

		buffer.writeu8(target, offset, 1)
		child_write_fresh(target, offset + 1, value)
	end

	local function read(source: buffer, offset: number, output: T?): T?
		local present = buffer.readu8(source, offset)

		if present == 0 then
			return nil
		elseif present ~= 1 then
			error(`Serdes.optional decoded invalid presence byte {present}`)
		end

		return child_read(source, offset + 1, output)
	end

	local function unsafe_read(source: buffer, offset: number, output: T?): T?
		if buffer.readu8(source, offset) == 0 then
			return nil
		end

		return child_unsafe_read(source, offset + 1, output)
	end

	return table.freeze({
		size = SIZE,
		nullable = true,
		delta_safe = codec.delta_safe == true,
		key_safe = codec.key_safe, key_less = codec.key_less :: any,
		wire_equal = wire_equal,

		validate = validate,
		unsafe_write = unsafe_write,
		write = write,
		unsafe_write_fresh = unsafe_write_fresh,
		write_fresh = write_fresh,
		read = read,
		unsafe_read = unsafe_read,
	})
end

--!strict
--!native

local Types = require("../Types")

type Codec<T> = Types.Codec<T>

local MAX_CAPACITY = 65_535

local function create_u8(capacity: number): Codec<string>
	local PREFIX_SIZE = 1
	local SIZE = PREFIX_SIZE + capacity

	local function validate(value: string): ()
		if type(value) ~= "string" then
			error(`Serdes.string({capacity}) expected string, got {typeof(value)}`)
		end

		if #value > capacity then
			error(`Serdes.string({capacity}) expected at most {capacity} bytes, got {#value}`)
		end
	end

	local function unsafe_write(target: buffer, offset: number, value: string): ()
		local length = #value
		local payload_offset = offset + PREFIX_SIZE

		buffer.writeu8(target, offset, length)

		if length > 0 then
			buffer.writestring(target, payload_offset, value)
		end

		local unused = capacity - length

		if unused > 0 then
			buffer.fill(target, payload_offset + length, 0, unused)
		end
	end

	local function unsafe_write_fresh(target: buffer, offset: number, value: string): ()
		local length = #value

		buffer.writeu8(target, offset, length)

		if length > 0 then
			buffer.writestring(target, offset + PREFIX_SIZE, value)
		end
	end

	local function write(target: buffer, offset: number, value: string): ()
		if type(value) ~= "string" then
			error(`Serdes.string({capacity}) expected string, got {typeof(value)}`)
		end

		local length = #value

		if length > capacity then
			error(`Serdes.string({capacity}) expected at most {capacity} bytes, got {length}`)
		end

		local payload_offset = offset + PREFIX_SIZE

		buffer.writeu8(target, offset, length)

		if length > 0 then
			buffer.writestring(target, payload_offset, value)
		end

		local unused = capacity - length

		if unused > 0 then
			buffer.fill(target, payload_offset + length, 0, unused)
		end
	end

	local function write_fresh(target: buffer, offset: number, value: string): ()
		if type(value) ~= "string" then
			error(`Serdes.string({capacity}) expected string, got {typeof(value)}`)
		end

		local length = #value

		if length > capacity then
			error(`Serdes.string({capacity}) expected at most {capacity} bytes, got {length}`)
		end

		buffer.writeu8(target, offset, length)

		if length > 0 then
			buffer.writestring(target, offset + PREFIX_SIZE, value)
		end
	end

	local function read(source: buffer, offset: number, _output: string?): string
		local length = buffer.readu8(source, offset)

		if length > capacity then
			error(`Serdes.string({capacity}) decoded invalid length {length}`)
		end

		if length == 0 then
			return ""
		end

		return buffer.readstring(source, offset + PREFIX_SIZE, length)
	end

	local function unsafe_read(source: buffer, offset: number, _output: string?): string
		local length = buffer.readu8(source, offset)

		if length == 0 then
			return ""
		end

		return buffer.readstring(source, offset + PREFIX_SIZE, length)
	end

	return table.freeze({
		size = SIZE,
		delta_safe = true,

		validate = validate,
		unsafe_write = unsafe_write,
		write = write,
		unsafe_write_fresh = unsafe_write_fresh,
		write_fresh = write_fresh,
		read = read,
		unsafe_read = unsafe_read,
	})
end

local function create_u16(capacity: number): Codec<string>
	local PREFIX_SIZE = 2
	local SIZE = PREFIX_SIZE + capacity

	local function validate(value: string): ()
		if type(value) ~= "string" then
			error(`Serdes.string({capacity}) expected string, got {typeof(value)}`)
		end

		if #value > capacity then
			error(`Serdes.string({capacity}) expected at most {capacity} bytes, got {#value}`)
		end
	end

	local function unsafe_write(target: buffer, offset: number, value: string): ()
		local length = #value
		local payload_offset = offset + PREFIX_SIZE

		buffer.writeu16(target, offset, length)

		if length > 0 then
			buffer.writestring(target, payload_offset, value)
		end

		local unused = capacity - length

		if unused > 0 then
			buffer.fill(target, payload_offset + length, 0, unused)
		end
	end

	local function unsafe_write_fresh(target: buffer, offset: number, value: string): ()
		local length = #value

		buffer.writeu16(target, offset, length)

		if length > 0 then
			buffer.writestring(target, offset + PREFIX_SIZE, value)
		end
	end

	local function write(target: buffer, offset: number, value: string): ()
		if type(value) ~= "string" then
			error(`Serdes.string({capacity}) expected string, got {typeof(value)}`)
		end

		local length = #value

		if length > capacity then
			error(`Serdes.string({capacity}) expected at most {capacity} bytes, got {length}`)
		end

		local payload_offset = offset + PREFIX_SIZE

		buffer.writeu16(target, offset, length)

		if length > 0 then
			buffer.writestring(target, payload_offset, value)
		end

		local unused = capacity - length

		if unused > 0 then
			buffer.fill(target, payload_offset + length, 0, unused)
		end
	end

	local function write_fresh(target: buffer, offset: number, value: string): ()
		if type(value) ~= "string" then
			error(`Serdes.string({capacity}) expected string, got {typeof(value)}`)
		end

		local length = #value

		if length > capacity then
			error(`Serdes.string({capacity}) expected at most {capacity} bytes, got {length}`)
		end

		buffer.writeu16(target, offset, length)

		if length > 0 then
			buffer.writestring(target, offset + PREFIX_SIZE, value)
		end
	end

	local function read(source: buffer, offset: number, _output: string?): string
		local length = buffer.readu16(source, offset)

		if length > capacity then
			error(`Serdes.string({capacity}) decoded invalid length {length}`)
		end

		if length == 0 then
			return ""
		end

		return buffer.readstring(source, offset + PREFIX_SIZE, length)
	end

	local function unsafe_read(source: buffer, offset: number, _output: string?): string
		local length = buffer.readu16(source, offset)

		if length == 0 then
			return ""
		end

		return buffer.readstring(source, offset + PREFIX_SIZE, length)
	end

	return table.freeze({
		size = SIZE,
		delta_safe = true,

		validate = validate,
		unsafe_write = unsafe_write,
		write = write,
		unsafe_write_fresh = unsafe_write_fresh,
		write_fresh = write_fresh,
		read = read,
		unsafe_read = unsafe_read,
	})
end

return function(capacity: number): Codec<string>
	if
		type(capacity) ~= "number"
		or not math.isfinite(capacity)
		or capacity % 1 ~= 0
		or capacity < 1
		or capacity > MAX_CAPACITY
	then
		error(`Serdes.string expected an integer capacity in [1, {MAX_CAPACITY}], got {capacity}`)
	end

	if capacity <= 255 then
		return create_u8(capacity)
	end

	return create_u16(capacity)
end

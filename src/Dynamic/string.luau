--!strict
--!native

local Types = require("../Types")

type DynamicCodec<T> = Types.DynamicCodec<T>
type WordWriter = (target: buffer, offset: number, value: number) -> ()
type WordReader = (source: buffer, offset: number) -> number

local MAX_U32 = 4_294_967_295

return function(maximum_length: number): DynamicCodec<string>
	if
		type(maximum_length) ~= "number"
		or not math.isfinite(maximum_length)
		or maximum_length % 1 ~= 0
		or maximum_length < 0
		or maximum_length > MAX_U32
	then
		error(`Serdes.dynamic.string expected integer maximum in [0, {MAX_U32}], got {maximum_length}`)
	end

	local PREFIX_SIZE: number
	local write_length: WordWriter
	local read_length: WordReader

	if maximum_length <= 255 then
		PREFIX_SIZE = 1
		write_length = buffer.writeu8
		read_length = buffer.readu8
	elseif maximum_length <= 65_535 then
		PREFIX_SIZE = 2
		write_length = buffer.writeu16
		read_length = buffer.readu16
	else
		PREFIX_SIZE = 4
		write_length = buffer.writeu32
		read_length = buffer.readu32
	end

	local function measure(value: string): number
		return PREFIX_SIZE + #value
	end

	local function unsafe_write(target: buffer, offset: number, value: string): number
		local length = #value
		local payload_offset = offset + PREFIX_SIZE

		write_length(target, offset, length)

		if length > 0 then
			buffer.writestring(target, payload_offset, value)
		end

		return payload_offset + length
	end

	local function write(target: buffer, offset: number, value: string): number
		if type(value) ~= "string" then
			error(`Serdes.dynamic.string expected string, got {typeof(value)}`)
		end

		local length = #value

		if length > maximum_length then
			error(`Serdes.dynamic.string expected at most {maximum_length} bytes, got {length}`)
		end

		local payload_offset = offset + PREFIX_SIZE

		write_length(target, offset, length)

		if length > 0 then
			buffer.writestring(target, payload_offset, value)
		end

		return payload_offset + length
	end

	local function read(source: buffer, offset: number, _output: string?): (string, number)
		local length = read_length(source, offset)

		if length > maximum_length then
			error(`Serdes.dynamic.string decoded invalid length {length}`)
		end

		local payload_offset = offset + PREFIX_SIZE

		if length == 0 then
			return "", payload_offset
		end

		return buffer.readstring(source, payload_offset, length), payload_offset + length
	end

	local function unsafe_read(source: buffer, offset: number, _output: string?): (string, number)
		local length = read_length(source, offset)
		local payload_offset = offset + PREFIX_SIZE

		if length == 0 then
			return "", payload_offset
		end

		return buffer.readstring(source, payload_offset, length), payload_offset + length
	end

	return table.freeze({
		measure = measure,
		unsafe_write = unsafe_write,
		write = write,
		read = read,
		unsafe_read = unsafe_read,
		value_like = true,
	})
end

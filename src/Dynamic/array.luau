--!strict
--!native

local Types = require("../Types")

type Array<T> = Types.Array<T>
type DynamicCodec<T> = Types.DynamicCodec<T>
type WordWriter = (target: buffer, offset: number, value: number) -> ()
type WordReader = (source: buffer, offset: number) -> number

local MAX_U32 = 4_294_967_295

return function<T>(element: DynamicCodec<T>, maximum_count: number): DynamicCodec<Array<T>>
	if
		type(maximum_count) ~= "number"
		or not math.isfinite(maximum_count)
		or maximum_count % 1 ~= 0
		or maximum_count < 0
		or maximum_count > MAX_U32
	then
		error(`Serdes.dynamic.array expected integer maximum in [0, {MAX_U32}], got {maximum_count}`)
	end

	local PREFIX_SIZE: number
	local write_count: WordWriter
	local read_count: WordReader

	if maximum_count <= 255 then
		PREFIX_SIZE = 1
		write_count = buffer.writeu8
		read_count = buffer.readu8
	elseif maximum_count <= 65_535 then
		PREFIX_SIZE = 2
		write_count = buffer.writeu16
		read_count = buffer.readu16
	else
		PREFIX_SIZE = 4
		write_count = buffer.writeu32
		read_count = buffer.readu32
	end

	local element_measure = element.measure
	local element_unsafe_write = element.unsafe_write
	local element_write = element.write
	local element_read = element.read
	local element_unsafe_read = element.unsafe_read

	local function measure(value: Array<T>): number
		local size = PREFIX_SIZE

		for index = 1, #value do
			size += element_measure(value[index])
		end

		return size
	end

	local function unsafe_write(target: buffer, offset: number, value: Array<T>): number
		local count = #value
		local next_offset = offset + PREFIX_SIZE

		write_count(target, offset, count)

		for index = 1, count do
			next_offset = element_unsafe_write(target, next_offset, value[index])
		end

		return next_offset
	end

	local function write(target: buffer, offset: number, value: Array<T>): number
		if type(value) ~= "table" then
			error(`Serdes.dynamic.array expected table, got {typeof(value)}`)
		end

		local count = #value

		if count > maximum_count then
			error(`Serdes.dynamic.array expected at most {maximum_count} elements, got {count}`)
		end

		local next_offset = offset + PREFIX_SIZE

		write_count(target, offset, count)

		for index = 1, count do
			next_offset = element_write(target, next_offset, value[index])
		end

		return next_offset
	end

	local function read(source: buffer, offset: number, output: Array<T>?): (Array<T>, number)
		local count = read_count(source, offset)

		if count > maximum_count then
			error(`Serdes.dynamic.array decoded invalid count {count}`)
		end

		local result = if output == nil then table.create(count) :: Array<T> else output
		local old_count = #result
		local next_offset = offset + PREFIX_SIZE

		for index = 1, count do
			local value: T
			value, next_offset = element_read(source, next_offset, result[index])
			result[index] = value
		end

		for index = old_count, count + 1, -1 do
			result[index] = nil :: any
		end

		return result, next_offset
	end

	local function unsafe_read(source: buffer, offset: number, output: Array<T>?): (Array<T>, number)
		local count = read_count(source, offset)
		local result = if output == nil then table.create(count) :: Array<T> else output
		local old_count = #result
		local next_offset = offset + PREFIX_SIZE

		for index = 1, count do
			local value: T
			value, next_offset = element_unsafe_read(source, next_offset, result[index])
			result[index] = value
		end

		for index = old_count, count + 1, -1 do
			result[index] = nil :: any
		end

		return result, next_offset
	end

	return table.freeze({
		measure = measure,
		unsafe_write = unsafe_write,
		write = write,
		read = read,
		unsafe_read = unsafe_read,
	})
end

--!strict
--!native

local Types = require("../Types")

type Array<T> = Types.Array<T>
type Dictionary<K, V> = Types.Dictionary<K, V>
type DynamicCodec<T> = Types.DynamicCodec<T>
type DynamicField<T> = Types.DynamicField<T>
type Measurer = (value: any) -> number
type Writer = (target: buffer, offset: number, value: any) -> number
type Reader = (source: buffer, offset: number, output: any?) -> (any, number)

return function<T>(fields: Array<DynamicField<T>>): DynamicCodec<T>
	local count = #fields

	if count == 0 then
		error("Serdes.dynamic.object expected at least one field")
	end

	local names = table.create(count) :: Array<string>
	local measurers = table.create(count) :: Array<Measurer>
	local unsafe_writers = table.create(count) :: Array<Writer>
	local writers = table.create(count) :: Array<Writer>
	local readers = table.create(count) :: Array<Reader>
	local unsafe_readers = table.create(count) :: Array<Reader>
	local seen: Dictionary<string, boolean> = {}

	for index = 1, count do
		local field = fields[index]
		local name = field.name
		local codec = field.codec

		if type(name) ~= "string" or name == "" then
			error(`Serdes.dynamic.object field {index} has an invalid name`)
		end

		if seen[name] then
			error(`Serdes.dynamic.object received duplicate field '{name}'`)
		end

		seen[name] = true
		names[index] = name
		measurers[index] = codec.measure
		unsafe_writers[index] = codec.unsafe_write
		writers[index] = codec.write
		readers[index] = codec.read
		unsafe_readers[index] = codec.unsafe_read
	end

	local function measure(value: T): number
		local record: Dictionary<string, any> = value :: any
		local size = 0

		for index = 1, count do
			size += measurers[index](record[names[index]])
		end

		return size
	end

	local function unsafe_write(target: buffer, offset: number, value: T): number
		local record: Dictionary<string, any> = value :: any
		local next_offset = offset

		for index = 1, count do
			next_offset = unsafe_writers[index](target, next_offset, record[names[index]])
		end

		return next_offset
	end

	local function write(target: buffer, offset: number, value: T): number
		if type(value) ~= "table" then
			error(`Serdes.dynamic.object expected table, got {typeof(value)}`)
		end

		local record: Dictionary<string, any> = value :: any
		local next_offset = offset

		for index = 1, count do
			next_offset = writers[index](target, next_offset, record[names[index]])
		end

		return next_offset
	end

	local function read(source: buffer, offset: number, output: T?): (T, number)
		local result = if output == nil then {} :: any else output
		local record: Dictionary<string, any> = result :: any
		local next_offset = offset

		for index = 1, count do
			local name = names[index]
			local value: any

			value, next_offset = readers[index](source, next_offset, record[name])
			record[name] = value
		end

		return result, next_offset
	end

	local function unsafe_read(source: buffer, offset: number, output: T?): (T, number)
		local result = if output == nil then {} :: any else output
		local record: Dictionary<string, any> = result :: any
		local next_offset = offset

		for index = 1, count do
			local name = names[index]
			local value: any

			value, next_offset = unsafe_readers[index](source, next_offset, record[name])
			record[name] = value
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

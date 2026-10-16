--!strict
--!native

local Types = require("../Types")
local schema_list = require("../Internal/schema_list")

type Array<T> = Types.Array<T>
type Dictionary<K, V> = Types.Dictionary<K, V>
type Codec<T> = Types.Codec<T>
type Field<T> = Types.Field<T>
type Record = {[string]: any}
type Validator<T> = (value: Record) -> ()
type Writer<T> = (target: buffer, offset: number, value: T) -> ()
type Reader<T> = (source: buffer, offset: number, output: T?) -> T

local function compile_validator(names: Array<string>, validators: Array<Validator<any>>, count: number): (value: Record) -> ()
	return function(value: Record): ()
		if type(value) ~= "table" then
			error(`Serdes.object expected table, got {typeof(value)}`)
		end

		local record: Dictionary<string, any> = value

		for index = 1, count do
			validators[index](record[names[index]])
		end
	end
end

local function compile_writer(
	names: Array<string>,
	offsets: Array<number>,
	writers: Array<Writer<any>>,
	count: number
): (target: buffer, offset: number, value: Record) -> ()
	return function(target: buffer, offset: number, value: Record): ()
		if type(value) ~= "table" then
			error(`Serdes.object expected table, got {typeof(value)}`)
		end

		local record: Dictionary<string, any> = value

		for index = 1, count do
			writers[index](target, offset + offsets[index], record[names[index]])
		end
	end
end

local function compile_unsafe_writer(
	names: Array<string>,
	offsets: Array<number>,
	writers: Array<Writer<any>>,
	count: number
): (target: buffer, offset: number, value: Record) -> ()
	return function(target: buffer, offset: number, value: Record): ()
		local record: Dictionary<string, any> = value

		for index = 1, count do
			writers[index](target, offset + offsets[index], record[names[index]])
		end
	end
end

local function compile_reader(
	names: Array<string>,
	offsets: Array<number>,
	readers: Array<Reader<any>>,
	count: number
): Reader<Record>
	return function(source: buffer, offset: number, output: Record?): Record
		local result: Record

		if output == nil then
			result = {} :: any
		else
			result = output
		end

		local record: Dictionary<string, any> = result :: any

		for index = 1, count do
			local name = names[index]

			record[name] = readers[index](source, offset + offsets[index], record[name])
		end

		return result
	end
end

return function(fields: Array<Field<any>>): Codec<Record>
	local count = schema_list(fields, "object")

	local names = table.create(count) :: Array<string>
	local offsets = table.create(count) :: Array<number>
	local codecs = table.create(count) :: Array<Codec<any>>

	local validators = table.create(count) :: Array<Validator<any>>
	local writers = table.create(count) :: Array<Writer<any>>
	local unsafe_writers = table.create(count) :: Array<Writer<any>>
	local fresh_writers = table.create(count) :: Array<Writer<any>>
	local unsafe_fresh_writers = table.create(count) :: Array<Writer<any>>
	local readers = table.create(count) :: Array<Reader<any>>
	local unsafe_readers = table.create(count) :: Array<Reader<any>>

	local seen: Dictionary<string, boolean> = {}
	local size = 0

	for index = 1, count do
		local field = fields[index]
		local name = field.name
		local codec = field.codec
		local length = codec.size

		if type(name) ~= "string" or name == "" then
			error(`Serdes.object field {index} has an invalid name`)
		end

		if seen[name] then
			error(`Serdes.object received duplicate field '{name}'`)
		end

		if not math.isfinite(length) or length % 1 ~= 0 or length < 0 then
			error(`Serdes.object field '{name}' has invalid codec size {length}`)
		end

		seen[name] = true

		names[index] = name
		offsets[index] = size
		codecs[index] = codec

		validators[index] = codec.validate
		writers[index] = codec.write
		unsafe_writers[index] = codec.unsafe_write
		fresh_writers[index] = codec.write_fresh
		unsafe_fresh_writers[index] = codec.unsafe_write_fresh
		readers[index] = codec.read
		unsafe_readers[index] = codec.unsafe_read

		size += length

		if not math.isfinite(size) or size > 1_073_741_824 then
			error("Serdes.object encoded size overflowed")
		end
	end

	table.freeze(names)
	table.freeze(codecs)

	return table.freeze({
		size = size,

		validate = compile_validator(names, validators, count),
		unsafe_write = compile_unsafe_writer(names, offsets, unsafe_writers, count),
		write = compile_writer(names, offsets, writers, count),
		unsafe_write_fresh = compile_unsafe_writer(names, offsets, unsafe_fresh_writers, count),
		write_fresh = compile_writer(names, offsets, fresh_writers, count),
		read = compile_reader(names, offsets, readers, count),
		unsafe_read = compile_reader(names, offsets, unsafe_readers, count),

		delta_names = names,
		delta_codecs = codecs,
	})
end

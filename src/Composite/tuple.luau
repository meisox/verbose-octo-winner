--!strict
--!native

local Types = require("../Types")
local schema_list = require("../Internal/schema_list")
local sequence = require("../Internal/sequence")

type Array<T> = Types.Array<T>
type Codec<T> = Types.Codec<T>
type Validator = (value: any) -> ()
type Writer = (target: buffer, offset: number, value: any) -> ()
type ChildReader = (source: buffer, offset: number, output: any?) -> any
type TupleReader = (source: buffer, offset: number, output: Array<any>?) -> Array<any>

local function compile_writer(
	offsets: Array<number>,
	writers: Array<Writer>,
	count: number,
	validate_value: ((value: Array<any>) -> ())?
): (target: buffer, offset: number, value: Array<any>) -> ()
	if validate_value then
		return function(target: buffer, offset: number, value: Array<any>): ()
			validate_value(value)

			for index = 1, count do
				writers[index](target, offset + offsets[index], value[index])
			end
		end
	end

	return function(target: buffer, offset: number, value: Array<any>): ()
		for index = 1, count do
			writers[index](target, offset + offsets[index], value[index])
		end
	end
end

local function compile_reader(offsets: Array<number>, readers: Array<ChildReader>, count: number): TupleReader
	return function(source: buffer, offset: number, output: Array<any>?): Array<any>
		local result = if output == nil then table.create(count) else output

		for index = 1, count do
			result[index] = readers[index](source, offset + offsets[index], result[index])
		end

		for index = #result, count + 1, -1 do result[index] = nil end
		return result
	end
end

return function(codecs: Array<Codec<any>>): Codec<Array<any>>
	local count = schema_list(codecs, "tuple")

	local offsets = table.create(count) :: Array<number>
	local validators = table.create(count) :: Array<Validator>
	local unsafe_writers = table.create(count) :: Array<Writer>
	local writers = table.create(count) :: Array<Writer>
	local unsafe_fresh_writers = table.create(count) :: Array<Writer>
	local fresh_writers = table.create(count) :: Array<Writer>
	local readers = table.create(count) :: Array<ChildReader>
	local unsafe_readers = table.create(count) :: Array<ChildReader>
	local size = 0
	local nullable = false

	for index = 1, count do
		local codec = codecs[index]
		local length = codec.size
		nullable = nullable or codec.nullable == true

		if not math.isfinite(length) or length % 1 ~= 0 or length < 0 then
			error(`Serdes.tuple codec {index} has invalid size {length}`)
		end

		offsets[index] = size
		validators[index] = codec.validate
		unsafe_writers[index] = codec.unsafe_write
		writers[index] = codec.write
		unsafe_fresh_writers[index] = codec.unsafe_write_fresh
		fresh_writers[index] = codec.write_fresh
		readers[index] = codec.read
		unsafe_readers[index] = codec.unsafe_read

		size += length

		if not math.isfinite(size) or size > 1_073_741_824 then
			error("Serdes.tuple encoded size overflowed")
		end
	end

	local validate_sequence = sequence(count, nullable, "tuple")
	local function validate(value: Array<any>): ()
		validate_sequence(value)

		for index = 1, count do
			validators[index](value[index])
		end
	end

	return table.freeze({
		size = size,

		validate = validate,
		unsafe_write = compile_writer(offsets, unsafe_writers, count, nil),
		write = compile_writer(offsets, writers, count, validate_sequence),
		unsafe_write_fresh = compile_writer(offsets, unsafe_fresh_writers, count, nil),
		write_fresh = compile_writer(offsets, fresh_writers, count, validate_sequence),
		read = compile_reader(offsets, readers, count),
		unsafe_read = compile_reader(offsets, unsafe_readers, count),
	})
end

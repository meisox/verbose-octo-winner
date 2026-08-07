--!strict
--!native

local Types = require("../Types")

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
	validate_value: boolean
): (target: buffer, offset: number, value: Array<any>) -> ()
	if validate_value then
		return function(target: buffer, offset: number, value: Array<any>): ()
			if type(value) ~= "table" then
				error(`Serdes.tuple expected table, got {typeof(value)}`)
			end

			local actual_count = #value

			if actual_count ~= count then
				error(`Serdes.tuple expected exactly {count} elements, got {actual_count}`)
			end

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

		return result
	end
end

return function(codecs: Array<Codec<any>>): Codec<Array<any>>
	local count = #codecs

	if count == 0 then
		error("Serdes.tuple expected at least one codec")
	end

	local offsets = table.create(count) :: Array<number>
	local validators = table.create(count) :: Array<Validator>
	local unsafe_writers = table.create(count) :: Array<Writer>
	local writers = table.create(count) :: Array<Writer>
	local unsafe_fresh_writers = table.create(count) :: Array<Writer>
	local fresh_writers = table.create(count) :: Array<Writer>
	local readers = table.create(count) :: Array<ChildReader>
	local unsafe_readers = table.create(count) :: Array<ChildReader>
	local size = 0

	for index = 1, count do
		local codec = codecs[index]
		local length = codec.size

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

		if not math.isfinite(size) then
			error("Serdes.tuple encoded size overflowed")
		end
	end

	local function validate(value: Array<any>): ()
		if type(value) ~= "table" then
			error(`Serdes.tuple expected table, got {typeof(value)}`)
		end

		local actual_count = #value

		if actual_count ~= count then
			error(`Serdes.tuple expected exactly {count} elements, got {actual_count}`)
		end

		for index = 1, count do
			validators[index](value[index])
		end
	end

	return table.freeze({
		size = size,

		validate = validate,
		unsafe_write = compile_writer(offsets, unsafe_writers, count, false),
		write = compile_writer(offsets, writers, count, true),
		unsafe_write_fresh = compile_writer(offsets, unsafe_fresh_writers, count, false),
		write_fresh = compile_writer(offsets, fresh_writers, count, true),
		read = compile_reader(offsets, readers, count),
		unsafe_read = compile_reader(offsets, unsafe_readers, count),
	})
end

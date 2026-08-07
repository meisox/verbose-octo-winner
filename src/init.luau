--!strict
--!native

local Types = require("@self/Types")

export type Codec<T> = Types.Codec<T>
export type DeltaCodec<T> = Types.DeltaCodec<T>
export type DynamicCodec<T> = Types.DynamicCodec<T>
export type DynamicField<T> = Types.DynamicField<T>
export type Field<T> = Types.Field<T>

type Array<T> = Types.Array<T>
type ArrayWriter<T> = Types.ArrayWriter<T>
type ArrayReader<T> = Types.ArrayReader<T>

local function field<T>(name: string, codec: Codec<T>): Field<T>
	if type(name) ~= "string" or name == "" then
		error(`Serdes.field expected a non-empty string name, got {name}`)
	end

	return table.freeze({
		name = name,
		codec = codec,
	})
end

local function encode<T>(codec: Codec<T>, value: T): buffer
	local target = buffer.create(codec.size)
	codec.write_fresh(target, 0, value)

	return target
end

local function unsafe_encode<T>(codec: Codec<T>, value: T): buffer
	local target = buffer.create(codec.size)
	codec.unsafe_write_fresh(target, 0, value)

	return target
end

local function into<T>(codec: Codec<T>, target: buffer, offset: number, value: T): number
	codec.write(target, offset, value)
	return offset + codec.size
end

local function unsafe_into<T>(codec: Codec<T>, target: buffer, offset: number, value: T): number
	codec.unsafe_write(target, offset, value)
	return offset + codec.size
end

local function decode<T>(codec: Codec<T>, source: buffer): T
	if type(source) ~= "buffer" then
		error(`Serdes.decode expected buffer, got {typeof(source)}`)
	end

	local expected = codec.size
	local actual = buffer.len(source)

	if actual ~= expected then
		error(`Serdes.decode expected exactly {expected} bytes, got {actual}`)
	end

	return codec.read(source, 0)
end

local function decode_into<T>(codec: Codec<T>, source: buffer, output: T): T
	if type(source) ~= "buffer" then
		error(`Serdes.decode_into expected buffer, got {typeof(source)}`)
	end

	local expected = codec.size
	local actual = buffer.len(source)

	if actual ~= expected then
		error(`Serdes.decode_into expected exactly {expected} bytes, got {actual}`)
	end

	return codec.read(source, 0, output)
end

local function unsafe_decode<T>(codec: Codec<T>, source: buffer): T
	return codec.unsafe_read(source, 0)
end

local function unsafe_decode_into<T>(codec: Codec<T>, source: buffer, output: T): T
	return codec.unsafe_read(source, 0, output)
end

local function from<T>(codec: Codec<T>, source: buffer, offset: number): (T, number)
	return codec.read(source, offset), offset + codec.size
end

local function from_into<T>(codec: Codec<T>, source: buffer, offset: number, output: T): (T, number)
	return codec.read(source, offset, output), offset + codec.size
end

local function unsafe_from<T>(codec: Codec<T>, source: buffer, offset: number): (T, number)
	return codec.unsafe_read(source, offset), offset + codec.size
end

local function unsafe_from_into<T>(codec: Codec<T>, source: buffer, offset: number, output: T): (T, number)
	return codec.unsafe_read(source, offset, output), offset + codec.size
end

local function encode_many<T>(codec: Codec<T>, values: Array<T>): buffer
	if type(values) ~= "table" then
		error(`Serdes.encode_many expected table, got {typeof(values)}`)
	end

	local count = #values
	local size = codec.size * count

	if not math.isfinite(size) then
		error("Serdes.encode_many encoded size overflowed")
	end

	local target = buffer.create(size)
	local bulk_write = codec.array_write_fresh

	if bulk_write ~= nil then
		local writer: ArrayWriter<T> = bulk_write
		writer(target, 0, values, count)
	else
		local writer = codec.write_fresh
		local offset = 0
		local stride = codec.size

		for index = 1, count do
			writer(target, offset, values[index])
			offset += stride
		end
	end

	return target
end

local function unsafe_encode_many<T>(codec: Codec<T>, values: Array<T>): buffer
	local count = #values
	local target = buffer.create(codec.size * count)
	local bulk_write = codec.array_unsafe_write_fresh

	if bulk_write ~= nil then
		local writer: ArrayWriter<T> = bulk_write
		writer(target, 0, values, count)
	else
		local writer = codec.unsafe_write_fresh
		local offset = 0
		local stride = codec.size

		for index = 1, count do
			writer(target, offset, values[index])
			offset += stride
		end
	end

	return target
end

local function decode_many_with<T>(
	codec: Codec<T>,
	source: buffer,
	count: number,
	output: Array<T>?,
	reader: (source: buffer, offset: number, output: T?) -> T,
	bulk_reader: ArrayReader<T>?
): Array<T>
	local result: Array<T>

	if bulk_reader ~= nil then
		local reader_many: ArrayReader<T> = bulk_reader
		result = reader_many(source, 0, count, output)
	else
		result = if output == nil then table.create(count) :: Array<T> else output
		local offset = 0
		local stride = codec.size

		for index = 1, count do
			result[index] = reader(source, offset, result[index])
			offset += stride
		end
	end

	for index = #result, count + 1, -1 do
		result[index] = nil :: any
	end

	return result
end

local function many_count<T>(codec: Codec<T>, source: buffer, api: string): number
	if type(source) ~= "buffer" then
		error(`Serdes.{api} expected buffer, got {typeof(source)}`)
	end

	local stride = codec.size

	if stride == 0 then
		error(`Serdes.{api} cannot infer count for a zero-sized codec`)
	end

	local size = buffer.len(source)

	if size % stride ~= 0 then
		error(`Serdes.{api} expected buffer length divisible by {stride}, got {size}`)
	end

	return size // stride
end

local function decode_many<T>(codec: Codec<T>, source: buffer): Array<T>
	local count = many_count(codec, source, "decode_many")
	return decode_many_with(codec, source, count, nil, codec.read, codec.array_read)
end

local function decode_many_into<T>(codec: Codec<T>, source: buffer, output: Array<T>): Array<T>
	local count = many_count(codec, source, "decode_many_into")
	return decode_many_with(codec, source, count, output, codec.read, codec.array_read)
end

local function unsafe_many_count<T>(codec: Codec<T>, source: buffer, api: string): number
	local stride = codec.size

	if stride == 0 then
		error(`Serdes.{api} cannot infer count for a zero-sized codec`)
	end

	return buffer.len(source) // stride
end

local function unsafe_decode_many<T>(codec: Codec<T>, source: buffer): Array<T>
	local count = unsafe_many_count(codec, source, "unsafe_decode_many")
	return decode_many_with(codec, source, count, nil, codec.unsafe_read, codec.array_unsafe_read)
end

local function unsafe_decode_many_into<T>(codec: Codec<T>, source: buffer, output: Array<T>): Array<T>
	local count = unsafe_many_count(codec, source, "unsafe_decode_many_into")
	return decode_many_with(codec, source, count, output, codec.unsafe_read, codec.array_unsafe_read)
end

return table.freeze({
	bool = require("@self/Primitive/bool"),
	bits = require("@self/Primitive/bits"),
	u8 = require("@self/Primitive/u8"),
	i8 = require("@self/Primitive/i8"),
	u16 = require("@self/Primitive/u16"),
	i16 = require("@self/Primitive/i16"),
	u32 = require("@self/Primitive/u32"),
	i32 = require("@self/Primitive/i32"),
	f32 = require("@self/Primitive/f32"),
	f64 = require("@self/Primitive/f64"),

	string = require("@self/Composite/string"),
	blob = require("@self/Composite/blob"),
	array = require("@self/Composite/array"),
	tuple = require("@self/Composite/tuple"),
	object = require("@self/Composite/object"),
	packed = require("@self/Composite/packed"),
	range = require("@self/Composite/range"),
	enum = require("@self/Composite/enum"),
	flags = require("@self/Composite/flags"),
	optional = require("@self/Composite/optional"),
	quantized = require("@self/Composite/quantized"),
	delta = require("@self/Delta"),
	dynamic = require("@self/Dynamic/init"),
	compressed = require("@self/Compressed"),

	color3_3 = require("@self/Roblox/color3_3"),
	color3_12 = require("@self/Roblox/color3_12"),

	vector2_5 = require("@self/Roblox/vector2_5"),
	vector2_8 = require("@self/Roblox/vector2_8"),
	vector3_8 = require("@self/Roblox/vector3_8"),
	vector3_12 = require("@self/Roblox/vector3_12"),

	cframe_12 = require("@self/Roblox/cframe_12"),
	cframe_28 = require("@self/Roblox/cframe_28"),
	cframe_48 = require("@self/Roblox/cframe_48"),

	udim_8 = require("@self/Roblox/udim_8"),
	udim2_16 = require("@self/Roblox/udim2_16"),

	field = field,

	encode = encode,
	unsafe_encode = unsafe_encode,

	into = into,
	unsafe_into = unsafe_into,

	decode = decode,
	unsafe_decode = unsafe_decode,
	decode_into = decode_into,
	unsafe_decode_into = unsafe_decode_into,

	from = from,
	unsafe_from = unsafe_from,
	from_into = from_into,
	unsafe_from_into = unsafe_from_into,

	encode_many = encode_many,
	unsafe_encode_many = unsafe_encode_many,
	decode_many = decode_many,
	unsafe_decode_many = unsafe_decode_many,
	decode_many_into = decode_many_into,
	unsafe_decode_many_into = unsafe_decode_many_into,
})

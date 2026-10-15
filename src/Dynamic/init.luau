--!strict
--!native

local Types = require("./Types")
local check_size = require("./Internal/size")
local check_bounds = require("./Internal/bounds")

type DynamicCodec<T> = Types.DynamicCodec<T>
type DynamicField<T> = Types.DynamicField<T>

local function field<T>(name: string, codec: Types.AnyCodec<T>): DynamicField<T>
	if type(name) ~= "string" or name == "" then
		error(`Serdes.dynamic.field expected a non-empty string name, got {name}`)
	end

	return table.freeze({
		name = name,
		codec = codec,
	})
end

local function encode<T>(codec: DynamicCodec<T>, value: T): buffer
	local size = codec.measure(value)
	if type(size) ~= "number" or size % 1 ~= 0 or size < 0 or size > 1_073_741_824 then
		error(`Serdes.dynamic.encode received invalid measured size {size}`)
	end
	local target = buffer.create(size)
	local writer = codec.unsafe_write_fresh or codec.unsafe_write
	local final_offset = writer(target, 0, value)

	if final_offset ~= size then
		error(`Serdes.dynamic.encode measured {size} bytes but wrote {final_offset}`)
	end

	return target
end

local function unsafe_encode<T>(codec: DynamicCodec<T>, value: T): buffer
	local target = buffer.create(codec.unsafe_measure(value))
	local writer = codec.unsafe_write_fresh or codec.unsafe_write
	writer(target, 0, value)
	return target
end

local function into<T>(codec: DynamicCodec<T>, target: buffer, offset: number, value: T): number
	check_bounds(target, offset, check_size(codec.measure(value)))
	return codec.unsafe_write(target, offset, value)
end

local function from<C>(codec: C & DynamicCodec<any>, source: buffer, offset: number, output: Types.Infer<C>?): (Types.Infer<C>, number)
	check_bounds(source, offset, codec.min_size)
	return codec.read(source, offset, output)
end

local function decode<C>(codec: C & DynamicCodec<any>, source: buffer): Types.Infer<C>
	if type(source) ~= "buffer" then
		error(`Serdes.dynamic.decode expected buffer, got {typeof(source)}`)
	end

	local value, final_offset = codec.read(source, 0)
	local size = buffer.len(source)

	if final_offset ~= size then
		error(`Serdes.dynamic.decode expected exactly {final_offset} bytes, got {size}`)
	end

	return value
end

local function unsafe_decode<C>(codec: C & DynamicCodec<any>, source: buffer): Types.Infer<C>
	local value = codec.unsafe_read(source, 0)
	return value
end

local function decode_into<C>(codec: C & DynamicCodec<any>, source: buffer, output: Types.Infer<C>): Types.Infer<C>
	if type(source) ~= "buffer" then
		error(`Serdes.dynamic.decode_into expected buffer, got {typeof(source)}`)
	end

	local value, final_offset = codec.read(source, 0, output)
	local size = buffer.len(source)

	if final_offset ~= size then
		error(`Serdes.dynamic.decode_into expected exactly {final_offset} bytes, got {size}`)
	end

	return value
end

local function unsafe_decode_into<C>(codec: C & DynamicCodec<any>, source: buffer, output: Types.Infer<C>): Types.Infer<C>
	local value = codec.unsafe_read(source, 0, output)
	return value
end

return table.freeze({
	field = field,
	fixed = require("@self/fixed"),
	string = require("@self/string"),
	array = require("@self/array"),
	object = require("@self/object"),
	struct = require("@self/struct"),
	tuple = require("@self/tuple"),
	optional = require("@self/optional"),
	blob = require("@self/blob"),
	union = require("@self/union"),
	map = require("@self/map"),
	varu32 = require("@self/varu32"),
	vari32 = require("@self/vari32"),
	delta_array = require("@self/delta_array"),
	rle = require("@self/rle"),

	encode = encode,
	into = into,
	from = from,
	unsafe_encode = unsafe_encode,
	decode = decode,
	unsafe_decode = unsafe_decode,
	decode_into = decode_into,
	unsafe_decode_into = unsafe_decode_into,
})

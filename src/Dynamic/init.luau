--!strict
--!native

local Types = require("../Types")

type DynamicCodec<T> = Types.DynamicCodec<T>
type DynamicField<T> = Types.DynamicField<T>

local function field<T>(name: string, codec: DynamicCodec<T>): DynamicField<T>
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
	local target = buffer.create(size)
	local final_offset = codec.write(target, 0, value)

	if final_offset ~= size then
		error(`Serdes.dynamic.encode measured {size} bytes but wrote {final_offset}`)
	end

	return target
end

local function unsafe_encode<T>(codec: DynamicCodec<T>, value: T): buffer
	local target = buffer.create(codec.measure(value))
	codec.unsafe_write(target, 0, value)
	return target
end

local function decode<T>(codec: DynamicCodec<T>, source: buffer): T
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

local function unsafe_decode<T>(codec: DynamicCodec<T>, source: buffer): T
	local value = codec.unsafe_read(source, 0)
	return value
end

local function decode_into<T>(codec: DynamicCodec<T>, source: buffer, output: T): T
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

local function unsafe_decode_into<T>(codec: DynamicCodec<T>, source: buffer, output: T): T
	local value = codec.unsafe_read(source, 0, output)
	return value
end

return table.freeze({
	field = field,
	fixed = require("./fixed"),
	string = require("./string"),
	array = require("./array"),
	object = require("./object"),
	varu32 = require("./varu32"),
	vari32 = require("./vari32"),
	delta_array = require("./delta_array"),
	rle = require("./rle"),

	encode = encode,
	unsafe_encode = unsafe_encode,
	decode = decode,
	unsafe_decode = unsafe_decode,
	decode_into = decode_into,
	unsafe_decode_into = unsafe_decode_into,
})

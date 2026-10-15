--!strict
--!native

local Types = require("../Types")
local schema_list = require("../Internal/schema_list")
local uint24 = require("../Internal/uint24")
local required_bits = require("../Internal/bits")

type Array<T> = Types.Array<T>
type Dictionary<K, V> = Types.Dictionary<K, V>
type Codec<T> = Types.Codec<T>

local MAX_COUNT = 4_294_967_296

return function<T>(values: Array<T>): Codec<T>
	local count = schema_list(values, "enum")

	if count == 0 then
		error("Serdes.enum expected at least one value")
	end

	if count > MAX_COUNT then
		error(`Serdes.enum cannot contain more than {MAX_COUNT} values`)
	end

	local to_id: Dictionary<T, number> = {}
	local to_value = table.create(count) :: Array<T>

	for index = 1, count do
		local value = values[index]

		if value == nil then
			error(`Serdes.enum value {index} cannot be nil`)
		end

		if type(value) == "number" and value ~= value then
			error(`Serdes.enum value {index} cannot be NaN`)
		end

		if to_id[value] ~= nil then
			error(`Serdes.enum received duplicate value at index {index}`)
		end

		local id = index - 1

		to_id[value] = id
		to_value[index] = value
	end

	local max_id = count - 1
	local bits = required_bits(max_id)

	local function validate(value: T): ()
		if to_id[value] == nil then
			error(`Serdes.enum received unknown value {tostring(value)}`)
		end
	end

	local function unsafe_pack(value: T): number
		return to_id[value]
	end

	local function pack(value: T): number
		local id = to_id[value]

		if id == nil then
			error(`Serdes.enum received unknown value {tostring(value)}`)
		end

		return id
	end

	local function unpack(id: number): T
		local value = to_value[id + 1]

		if value == nil then
			error(`Serdes.enum decoded unknown id {id}`)
		end

		return value
	end

	local function unsafe_unpack(id: number): T
		return to_value[id + 1] :: any
	end

	if count == 1 then
		local only = to_value[1]

		local function unsafe_write(_target: buffer, _offset: number, _value: T): () end

		local function write(_target: buffer, _offset: number, value: T): ()
			if to_id[value] == nil then
				error(`Serdes.enum received unknown value {tostring(value)}`)
			end
		end

		local function read(_source: buffer, _offset: number, _output: T?): T
			return only
		end

		return table.freeze({
			size = 0,
			delta_safe = true, key_safe = true,

			validate = validate,
			unsafe_write = unsafe_write,
			write = write,
			unsafe_write_fresh = unsafe_write,
			write_fresh = write,
			read = read,
			unsafe_read = read,

			bits = bits,
			unsafe_pack = unsafe_pack,
			pack = pack,
			unpack = unpack,
			unsafe_unpack = unsafe_unpack,
		})
	elseif max_id <= 255 then
		local function unsafe_write(target: buffer, offset: number, value: T): ()
			buffer.writeu8(target, offset, to_id[value])
		end

		local function write(target: buffer, offset: number, value: T): ()
			local id = to_id[value]
			if id == nil then
				error(`Serdes.enum received unknown value {tostring(value)}`)
			end

			buffer.writeu8(target, offset, id)
		end

		local function read(source: buffer, offset: number, _output: T?): T
			local id = buffer.readu8(source, offset)
			local value = to_value[id + 1]

			if value == nil then
				error(`Serdes.enum decoded unknown id {id}`)
			end

			return value
		end

		local function unsafe_read(source: buffer, offset: number, _output: T?): T
			return to_value[buffer.readu8(source, offset) + 1] :: any
		end

		return table.freeze({
			size = 1,
			delta_safe = true, key_safe = true,

			validate = validate,
			unsafe_write = unsafe_write,
			write = write,
			unsafe_write_fresh = unsafe_write,
			write_fresh = write,
			read = read,
			unsafe_read = unsafe_read,

			bits = bits,
			unsafe_pack = unsafe_pack,
			pack = pack,
			unpack = unpack,
			unsafe_unpack = unsafe_unpack,
		})
	elseif max_id <= 65_535 then
		local function unsafe_write(target: buffer, offset: number, value: T): ()
			buffer.writeu16(target, offset, to_id[value])
		end

		local function write(target: buffer, offset: number, value: T): ()
			local id = to_id[value]
			if id == nil then
				error(`Serdes.enum received unknown value {tostring(value)}`)
			end

			buffer.writeu16(target, offset, id)
		end

		local function read(source: buffer, offset: number, _output: T?): T
			local id = buffer.readu16(source, offset)
			local value = to_value[id + 1]

			if value == nil then
				error(`Serdes.enum decoded unknown id {id}`)
			end

			return value
		end

		local function unsafe_read(source: buffer, offset: number, _output: T?): T
			return to_value[buffer.readu16(source, offset) + 1] :: any
		end

		return table.freeze({
			size = 2,
			delta_safe = true, key_safe = true,

			validate = validate,
			unsafe_write = unsafe_write,
			write = write,
			unsafe_write_fresh = unsafe_write,
			write_fresh = write,
			read = read,
			unsafe_read = unsafe_read,

			bits = bits,
			unsafe_pack = unsafe_pack,
			pack = pack,
			unpack = unpack,
			unsafe_unpack = unsafe_unpack,
		})
	elseif max_id <= 16_777_215 then
		local function unsafe_write(target: buffer, offset: number, value: T): ()
			uint24.write(target, offset, to_id[value])
		end

		local function write(target: buffer, offset: number, value: T): ()
			local id = to_id[value]
			if id == nil then
				error(`Serdes.enum received unknown value {tostring(value)}`)
			end

			uint24.write(target, offset, id)
		end

		local function read(source: buffer, offset: number, _output: T?): T
			local id = uint24.read(source, offset)
			local value = to_value[id + 1]

			if value == nil then
				error(`Serdes.enum decoded unknown id {id}`)
			end

			return value
		end

		local function unsafe_read(source: buffer, offset: number, _output: T?): T
			return to_value[uint24.read(source, offset) + 1] :: any
		end

		return table.freeze({
			size = 3,
			delta_safe = true, key_safe = true,

			validate = validate,
			unsafe_write = unsafe_write,
			write = write,
			unsafe_write_fresh = unsafe_write,
			write_fresh = write,
			read = read,
			unsafe_read = unsafe_read,

			bits = bits,
			unsafe_pack = unsafe_pack,
			pack = pack,
			unpack = unpack,
			unsafe_unpack = unsafe_unpack,
		})	else
		local function unsafe_write(target: buffer, offset: number, value: T): ()
			buffer.writeu32(target, offset, to_id[value])
		end

		local function write(target: buffer, offset: number, value: T): ()
			local id = to_id[value]
			if id == nil then
				error(`Serdes.enum received unknown value {tostring(value)}`)
			end

			buffer.writeu32(target, offset, id)
		end

		local function read(source: buffer, offset: number, _output: T?): T
			local id = buffer.readu32(source, offset)
			local value = to_value[id + 1]

			if value == nil then
				error(`Serdes.enum decoded unknown id {id}`)
			end

			return value
		end

		local function unsafe_read(source: buffer, offset: number, _output: T?): T
			return to_value[buffer.readu32(source, offset) + 1] :: any
		end

		return table.freeze({
			size = 4,
			delta_safe = true, key_safe = true,

			validate = validate,
			unsafe_write = unsafe_write,
			write = write,
			unsafe_write_fresh = unsafe_write,
			write_fresh = write,
			read = read,
			unsafe_read = unsafe_read,

			bits = bits,
			unsafe_pack = unsafe_pack,
			pack = pack,
			unpack = unpack,
			unsafe_unpack = unsafe_unpack,
		})
	end
end

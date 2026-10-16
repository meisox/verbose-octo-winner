--!strict
--!native

local Types = require("./Types")
local uint24 = require("./Internal/uint24")
local wide = require("./Internal/delta_wide")

type Array<T> = Types.Array<T>
type Dictionary<K, V> = Types.Dictionary<K, V>
type Codec<T> = Types.Codec<T>
type DeltaCodec<T> = Types.DeltaCodec<T>
type Writer = (target: buffer, offset: number, value: any) -> ()
type Reader = (source: buffer, offset: number, output: any?) -> any
type DeltaSchema<T> = Codec<T> & {
	delta_names: Array<string>?,
	delta_codecs: Array<Codec<any>>?,
}

local function write_zero(_target: buffer, _offset: number, _value: number): () end
local function read_zero(_source: buffer, _offset: number): number return 0 end

return function<T>(schema: Codec<T>): DeltaCodec<T>
	local metadata = schema :: DeltaSchema<T>
	local names: Array<string>? = metadata.delta_names
	local codecs: Array<Codec<any>>? = metadata.delta_codecs

	if names == nil or codecs == nil then
		error("Serdes.delta expected a Serdes.object codec")
	end

	local count = #names

	if count > 32 then
		return wide(names, codecs) :: any
	end
	local header_size = math.ceil(count / 8)
	local write_mask = if header_size == 0 then write_zero elseif header_size == 1 then buffer.writeu8 elseif header_size == 2 then buffer.writeu16 elseif header_size == 3 then uint24.write else buffer.writeu32
	local read_mask = if header_size == 0 then read_zero elseif header_size == 1 then buffer.readu8 elseif header_size == 2 then buffer.readu16 elseif header_size == 3 then uint24.read else buffer.readu32

	local sizes = table.create(count) :: Array<number>
	local masks = table.create(count) :: Array<number>
	local unsafe_writers = table.create(count) :: Array<Writer>
	local readers = table.create(count) :: Array<Reader>
	local unsafe_readers = table.create(count) :: Array<Reader>
	local validators = table.create(count) :: Array<(value: any) -> ()>
	local equivalents: {((any, any) -> boolean)?} = {}

	for index = 1, count do
		local codec = codecs[index]

		if codec.delta_safe ~= true then
			error(`Serdes.delta field '{names[index]}' codec is not value-like`)
		end

		sizes[index] = codec.size
		masks[index] = bit32.lshift(1, index - 1)
		unsafe_writers[index] = codec.unsafe_write_fresh
		readers[index] = codec.read
		unsafe_readers[index] = codec.unsafe_read
		validators[index] = codec.validate
		equivalents[index] = codec.wire_equal
	end

	local unused_mask = if count == 32 then 0 else bit32.bnot(2 ^ count - 1)

	local function encode(baseline: T, current: T): buffer
		if type(baseline) ~= "table" then
			error(`Serdes.delta encode expected baseline table, got {typeof(baseline)}`)
		end

		if type(current) ~= "table" then
			error(`Serdes.delta encode expected current table, got {typeof(current)}`)
		end

		local baseline_record: Dictionary<string, any> = baseline :: any
		local current_record: Dictionary<string, any> = current :: any
		local mask = 0
		local payload_size = 0

		for index = 1, count do
			local name = names[index]
			validators[index](current_record[name])

			local equal = equivalents[index]
			if current_record[name] ~= baseline_record[name] and (equal == nil or not equal(current_record[name], baseline_record[name])) then
				mask = bit32.bor(mask, masks[index])
				payload_size += sizes[index]
			end
		end

		local target = buffer.create(header_size + payload_size)
		write_mask(target, 0, mask)

		local offset = header_size

		for index = 1, count do
			if bit32.btest(mask, masks[index]) then
				unsafe_writers[index](target, offset, current_record[names[index]])
				offset += sizes[index]
			end
		end

		return target
	end

	local function unsafe_encode(baseline: T, current: T): buffer
		local baseline_record: Dictionary<string, any> = baseline :: any
		local current_record: Dictionary<string, any> = current :: any
		local mask = 0
		local payload_size = 0

		for index = 1, count do
			local name = names[index]

			local equal = equivalents[index]
			if current_record[name] ~= baseline_record[name] and (equal == nil or not equal(current_record[name], baseline_record[name])) then
				mask = bit32.bor(mask, masks[index])
				payload_size += sizes[index]
			end
		end

		local target = buffer.create(header_size + payload_size)
		write_mask(target, 0, mask)

		local offset = header_size

		for index = 1, count do
			if bit32.btest(mask, masks[index]) then
				unsafe_writers[index](target, offset, current_record[names[index]])
				offset += sizes[index]
			end
		end

		return target
	end

	local function decode_into(source: buffer, output: T): T
		if type(source) ~= "buffer" then
			error(`Serdes.delta decode_into expected buffer, got {typeof(source)}`)
		end

		local mask = read_mask(source, 0)

		if unused_mask ~= 0 and bit32.band(mask, unused_mask) ~= 0 then
			error(`Serdes.delta decoded invalid change mask {mask}`)
		end

		if type(output) ~= "table" or table.isfrozen(output :: any) or getmetatable(output :: any) ~= nil then
			error("Serdes.delta decode_into expected a plain writable baseline table")
		end

		local expected = header_size
		for index = 1, count do
			if bit32.btest(mask, masks[index]) then
				expected += sizes[index]
			end
		end
		if expected ~= buffer.len(source) then
			error(`Serdes.delta expected exactly {expected} bytes, got {buffer.len(source)}`)
		end

		local record: Dictionary<string, any> = output :: any
		local pending = table.create(count)
		local offset = header_size

		for index = 1, count do
			if bit32.btest(mask, masks[index]) then
				pending[index] = readers[index](source, offset)
				offset += sizes[index]
			end
		end

		-- Value-like fields can be staged without mutating the caller's baseline.
		for index = 1, count do
			if bit32.btest(mask, masks[index]) then
				record[names[index]] = pending[index]
			end
		end

		return output :: T
	end

	local function unsafe_decode_into(source: buffer, output: T): T
		local mask = read_mask(source, 0)
		local record: Dictionary<string, any> = output :: any
		local offset = header_size

		for index = 1, count do
			if bit32.btest(mask, masks[index]) then
				local name = names[index]

				record[name] = unsafe_readers[index](source, offset, record[name])
				offset += sizes[index]
			end
		end

		return output
	end

	return table.freeze({
		encode = encode,
		unsafe_encode = unsafe_encode,
		decode_into = decode_into,
		unsafe_decode_into = unsafe_decode_into,
	})
end

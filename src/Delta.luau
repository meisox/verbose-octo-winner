--!strict
--!native

local Types = require("./Types")

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

return function<T>(schema: Codec<T>): DeltaCodec<T>
	local metadata = schema :: DeltaSchema<T>
	local names: Array<string>? = metadata.delta_names
	local codecs: Array<Codec<any>>? = metadata.delta_codecs

	if names == nil or codecs == nil then
		error("Serdes.delta expected a Serdes.object codec")
	end

	local count = #names

	if count > 32 then
		error("Serdes.delta cannot contain more than 32 fields")
	end

	local sizes = table.create(count) :: Array<number>
	local masks = table.create(count) :: Array<number>
	local unsafe_writers = table.create(count) :: Array<Writer>
	local writers = table.create(count) :: Array<Writer>
	local readers = table.create(count) :: Array<Reader>
	local unsafe_readers = table.create(count) :: Array<Reader>

	for index = 1, count do
		local codec = codecs[index]

		if codec.delta_safe ~= true then
			error(`Serdes.delta field '{names[index]}' codec is not value-like`)
		end

		sizes[index] = codec.size
		masks[index] = bit32.lshift(1, index - 1)
		unsafe_writers[index] = codec.unsafe_write_fresh
		writers[index] = codec.write_fresh
		readers[index] = codec.read
		unsafe_readers[index] = codec.unsafe_read
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

			if current_record[name] ~= baseline_record[name] then
				mask = bit32.bor(mask, masks[index])
				payload_size += sizes[index]
			end
		end

		local target = buffer.create(4 + payload_size)
		buffer.writeu32(target, 0, mask)

		local offset = 4

		for index = 1, count do
			if bit32.btest(mask, masks[index]) then
				writers[index](target, offset, current_record[names[index]])
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

			if current_record[name] ~= baseline_record[name] then
				mask = bit32.bor(mask, masks[index])
				payload_size += sizes[index]
			end
		end

		local target = buffer.create(4 + payload_size)
		buffer.writeu32(target, 0, mask)

		local offset = 4

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

		local mask = buffer.readu32(source, 0)

		if unused_mask ~= 0 and bit32.band(mask, unused_mask) ~= 0 then
			error(`Serdes.delta decoded invalid change mask {mask}`)
		end

		local record: Dictionary<string, any> = output :: any
		local offset = 4

		for index = 1, count do
			if bit32.btest(mask, masks[index]) then
				local name = names[index]

				record[name] = readers[index](source, offset, record[name])
				offset += sizes[index]
			end
		end

		local actual = buffer.len(source)

		if offset ~= actual then
			error(`Serdes.delta expected exactly {offset} bytes, got {actual}`)
		end

		return output
	end

	local function unsafe_decode_into(source: buffer, output: T): T
		local mask = buffer.readu32(source, 0)
		local record: Dictionary<string, any> = output :: any
		local offset = 4

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

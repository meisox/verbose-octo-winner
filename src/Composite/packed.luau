--!strict
--!native

local Types = require("../Types")
local schema_list = require("../Internal/schema_list")
local uint24 = require("../Internal/uint24")

type Array<T> = Types.Array<T>
type Dictionary<K, V> = Types.Dictionary<K, V>
type Codec<T> = Types.Codec<T>
type Field<T> = Types.Field<T>
type Packer<T> = (value: T) -> number
type Unpacker<T> = (value: number) -> T
type WordWriter = (target: buffer, offset: number, value: number) -> ()
type WordReader = (source: buffer, offset: number) -> number

local function write_zero(_target: buffer, _offset: number, _value: number): () end

local function read_zero(_source: buffer, _offset: number): number
	return 0
end

type Record = {[string]: any}

return function(fields: Array<Field<any>>): Codec<Record>
	local count = schema_list(fields, "packed")

	local names = table.create(count) :: Array<string>
	local packers = table.create(count) :: Array<Packer<any>>

	local packed_names = table.create(count) :: Array<string>
	local shifts = table.create(count) :: Array<number>
	local widths = table.create(count) :: Array<number>
	local unsafe_packers = table.create(count) :: Array<Packer<any>>
	local packed_packers = table.create(count) :: Array<Packer<any>>
	local unpackers = table.create(count) :: Array<Unpacker<any>>
	local unsafe_unpackers = table.create(count) :: Array<Unpacker<any>>

	local zero_names = table.create(count) :: Array<string>
	local zero_packers = table.create(count) :: Array<Packer<any>>
	local zero_unpackers = table.create(count) :: Array<Unpacker<any>>
	local zero_unsafe_unpackers = table.create(count) :: Array<Unpacker<any>>

	local seen: Dictionary<string, boolean> = {}
	local packed_count = 0
	local zero_count = 0
	local total_bits = 0

	for index = 1, count do
		local field = fields[index]
		local name = field.name
		local codec = field.codec

		if type(name) ~= "string" or name == "" then
			error(`Serdes.packed field {index} has an invalid name`)
		end

		if seen[name] then
			error(`Serdes.packed received duplicate field '{name}'`)
		end

		local width = codec.bits
		local unsafe_packer = codec.unsafe_pack
		local packer = codec.pack
		local unpacker = codec.unpack
		local unsafe_unpacker = codec.unsafe_unpack

		if
			type(width) ~= "number"
			or not math.isfinite(width)
			or width % 1 ~= 0
			or width < 0
			or width > 32
			or type(unsafe_packer) ~= "function"
			or type(packer) ~= "function"
			or type(unpacker) ~= "function"
			or type(unsafe_unpacker) ~= "function"
		then
			error(`Serdes.packed field '{name}' codec is not packable`)
		end

		if total_bits + width > 8_589_934_592 then
			error("Serdes.packed encoded size exceeds the maximum buffer size")
		end

		seen[name] = true
		names[index] = name
		packers[index] = packer

		if width == 0 then
			zero_count += 1
			zero_names[zero_count] = name
			zero_packers[zero_count] = packer
			zero_unpackers[zero_count] = unpacker
			zero_unsafe_unpackers[zero_count] = unsafe_unpacker
		else
			packed_count += 1
			packed_names[packed_count] = name
			shifts[packed_count] = total_bits
			widths[packed_count] = width
			unsafe_packers[packed_count] = unsafe_packer
			packed_packers[packed_count] = packer
			unpackers[packed_count] = unpacker
			unsafe_unpackers[packed_count] = unsafe_unpacker
		end

		total_bits += width
	end

	-- Keep the single-word implementation below for small records. Larger
	-- records use native bit accesses, including fields crossing word boundaries.
	if total_bits > 32 then
		local size = math.ceil(total_bits / 8)
		local padding = size * 8 - total_bits
		local function validate(value: Record): ()
			if type(value) ~= "table" then error("Serdes.packed expected table") end
			local record = value :: any
			for index = 1, count do packers[index](record[names[index]]) end
		end
		local function compile_writer(selected: Array<Packer<any>>, checked: boolean)
			return function(target: buffer, offset: number, value: Record): ()
				if checked and type(value) ~= "table" then error("Serdes.packed expected table") end
				local record = value :: any
				local start = offset * 8
				for index = 1, packed_count do
					buffer.writebits(target, start + shifts[index], widths[index], selected[index](record[packed_names[index]]))
				end
				if checked then
					for index = 1, zero_count do zero_packers[index](record[zero_names[index]]) end
				end
				if padding > 0 then buffer.writebits(target, start + total_bits, padding, 0) end
			end
		end
		local function compile_reader(selected: Array<Unpacker<any>>, zero_selected: Array<Unpacker<any>>, checked: boolean)
			return function(source: buffer, offset: number, output: Record?): Record
				local record = if output == nil then {} else output :: any
				local start = offset * 8
				if checked and padding > 0 and buffer.readbits(source, start + total_bits, padding) ~= 0 then
					error("Serdes.packed decoded nonzero padding bits")
				end
				for index = 1, packed_count do
					record[packed_names[index]] = selected[index](buffer.readbits(source, start + shifts[index], widths[index]))
				end
				for index = 1, zero_count do record[zero_names[index]] = zero_selected[index](0) end
				return record
			end
		end
		local write = compile_writer(packed_packers, true)
		local unsafe_write = compile_writer(unsafe_packers, false)
		return table.freeze({
			size = size, validate = validate,
			write = write, unsafe_write = unsafe_write,
			write_fresh = write, unsafe_write_fresh = unsafe_write,
			read = compile_reader(unpackers, zero_unpackers, true),
			unsafe_read = compile_reader(unsafe_unpackers, zero_unsafe_unpackers, false),
		})
	end

	local SIZE: number
	local storage_bits: number
	local write_word: WordWriter
	local raw_read_word: WordReader

	if total_bits == 0 then
		SIZE = 0
		storage_bits = 0
		write_word = write_zero
		raw_read_word = read_zero
	elseif total_bits <= 8 then
		SIZE = 1
		storage_bits = 8
		write_word = buffer.writeu8
		raw_read_word = buffer.readu8
	elseif total_bits <= 16 then
		SIZE = 2
		storage_bits = 16
		write_word = buffer.writeu16
		raw_read_word = buffer.readu16
	elseif total_bits <= 24 then
		SIZE = 3
		storage_bits = 24
		write_word = uint24.write
		raw_read_word = uint24.read
	else
		SIZE = 4
		storage_bits = 32
		write_word = buffer.writeu32
		raw_read_word = buffer.readu32
	end

	local read_word: WordReader

	if total_bits == storage_bits then
		read_word = raw_read_word
	else
		local unused_mask = bit32.bnot(2 ^ total_bits - 1)

		read_word = function(source: buffer, offset: number): number
			local word = raw_read_word(source, offset)

			if bit32.band(word, unused_mask) ~= 0 then
				error(`Serdes.packed decoded noncanonical value {word}`)
			end

			return word
		end
	end

	local function validate(value: Record): ()
		if type(value) ~= "table" then
			error(`Serdes.packed expected table, got {typeof(value)}`)
		end

		local record: Dictionary<string, any> = value :: any

		for index = 1, count do
			packers[index](record[names[index]])
		end
	end

	local function unsafe_write(target: buffer, offset: number, value: Record): ()
		local record: Dictionary<string, any> = value :: any
		local word = 0

		for index = 1, packed_count do
			word = bit32.bor(word, bit32.lshift(unsafe_packers[index](record[packed_names[index]]), shifts[index]))
		end

		write_word(target, offset, word)
	end

	local function write(target: buffer, offset: number, value: Record): ()
		if type(value) ~= "table" then
			error(`Serdes.packed expected table, got {typeof(value)}`)
		end

		local record: Dictionary<string, any> = value :: any
		local word = 0

		for index = 1, packed_count do
			word = bit32.bor(word, bit32.lshift(packed_packers[index](record[packed_names[index]]), shifts[index]))
		end

		for index = 1, zero_count do
			zero_packers[index](record[zero_names[index]])
		end

		write_word(target, offset, word)
	end

	local function read(source: buffer, offset: number, output: Record?): Record
		local result = if output == nil then {} :: any else output
		local record: Dictionary<string, any> = result :: any
		local word = read_word(source, offset)

		for index = 1, packed_count do
			record[packed_names[index]] = unpackers[index](bit32.extract(word, shifts[index], widths[index]))
		end

		for index = 1, zero_count do
			record[zero_names[index]] = zero_unpackers[index](0)
		end

		return result
	end

	local function unsafe_read(source: buffer, offset: number, output: Record?): Record
		local result = if output == nil then {} :: any else output
		local record: Dictionary<string, any> = result :: any
		local word = raw_read_word(source, offset)

		for index = 1, packed_count do
			record[packed_names[index]] = unsafe_unpackers[index](bit32.extract(word, shifts[index], widths[index]))
		end

		for index = 1, zero_count do
			record[zero_names[index]] = zero_unsafe_unpackers[index](0)
		end

		return result
	end

	return table.freeze({
		size = SIZE,

		validate = validate,
		unsafe_write = unsafe_write,
		write = write,
		unsafe_write_fresh = unsafe_write,
		write_fresh = write,
		read = read,
		unsafe_read = unsafe_read,
	})
end

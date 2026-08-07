--!strict
--!native

local Types = require("../Types")

type Codec<T> = Types.Codec<T>
type WordWriter = (target: buffer, offset: number, value: number) -> ()
type WordReader = (source: buffer, offset: number) -> number
type Reader = (source: buffer, offset: number, output: number?) -> number

local MAX_U32 = 4_294_967_295

return function(bit_count: number): Codec<number>
	if
		type(bit_count) ~= "number"
		or not math.isfinite(bit_count)
		or bit_count % 1 ~= 0
		or bit_count < 1
		or bit_count > 32
	then
		error(`Serdes.bits expected integer bit count in [1, 32], got {bit_count}`)
	end

	local maximum = if bit_count == 32 then MAX_U32 else 2 ^ bit_count - 1
	local size: number
	local write_word: WordWriter
	local read_word: WordReader

	if bit_count <= 8 then
		size = 1
		write_word = buffer.writeu8
		read_word = buffer.readu8
	elseif bit_count <= 16 then
		size = 2
		write_word = buffer.writeu16
		read_word = buffer.readu16
	else
		size = 4
		write_word = buffer.writeu32
		read_word = buffer.readu32
	end

	local function validate(value: number): ()
		if type(value) ~= "number" then
			error(`Serdes.bits({bit_count}) expected number, got {typeof(value)}`)
		end

		if value % 1 ~= 0 or value < 0 or value > maximum then
			error(`Serdes.bits({bit_count}) expected integer in [0, {maximum}], got {value}`)
		end
	end

	local function unsafe_write(target: buffer, offset: number, value: number): ()
		write_word(target, offset, value)
	end

	local function write(target: buffer, offset: number, value: number): ()
		if type(value) ~= "number" then
			error(`Serdes.bits({bit_count}) expected number, got {typeof(value)}`)
		end

		if value % 1 ~= 0 or value < 0 or value > maximum then
			error(`Serdes.bits({bit_count}) expected integer in [0, {maximum}], got {value}`)
		end

		write_word(target, offset, value)
	end

	local read: Reader

	if bit_count == 8 or bit_count == 16 or bit_count == 32 then
		read = function(source: buffer, offset: number, _output: number?): number
			return read_word(source, offset)
		end
	else
		read = function(source: buffer, offset: number, _output: number?): number
			local value = read_word(source, offset)

			if value > maximum then
				error(`Serdes.bits({bit_count}) decoded invalid value {value}`)
			end

			return value
		end
	end

	local function unsafe_read(source: buffer, offset: number, _output: number?): number
		return read_word(source, offset)
	end

	local function unsafe_pack(value: number): number
		return value
	end

	local function pack(value: number): number
		if type(value) ~= "number" then
			error(`Serdes.bits({bit_count}) expected number, got {typeof(value)}`)
		end

		if value % 1 ~= 0 or value < 0 or value > maximum then
			error(`Serdes.bits({bit_count}) expected integer in [0, {maximum}], got {value}`)
		end

		return value
	end

	local function unpack(value: number): number
		return value
	end

	return table.freeze({
		size = size,
		delta_safe = true,

		validate = validate,
		unsafe_write = unsafe_write,
		write = write,
		unsafe_write_fresh = unsafe_write,
		write_fresh = write,
		read = read,
		unsafe_read = unsafe_read,

		bits = bit_count,
		unsafe_pack = unsafe_pack,
		pack = pack,
		unpack = unpack,
		unsafe_unpack = unpack,
	})
end

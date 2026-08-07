--!strict
--!native

local Types = require("../Types")

type Array<T> = Types.Array<T>
type Dictionary<K, V> = Types.Dictionary<K, V>
type Codec<T> = Types.Codec<T>
type Flags = Types.Flags

return function(names: Array<string>): Codec<Flags>
	local count = #names

	if count == 0 then
		error("Serdes.flags expected at least one flag")
	end

	local compiled = table.create(count) :: Array<string>
	local seen: Dictionary<string, boolean> = {}

	for index = 1, count do
		local name = names[index]

		if type(name) ~= "string" or name == "" then
			error(`Serdes.flags received invalid name at index {index}`)
		end

		if seen[name] then
			error(`Serdes.flags received duplicate flag '{name}'`)
		end

		seen[name] = true
		compiled[index] = name
	end

	local full_byte_count = count // 8
	local tail_bit_count = count % 8
	local tail_maximum = 2 ^ tail_bit_count - 1
	local SIZE = full_byte_count + if tail_bit_count == 0 then 0 else 1

	local function validate(value: Flags): ()
		if type(value) ~= "table" then
			error(`Serdes.flags expected table, got {typeof(value)}`)
		end

		for index = 1, count do
			local flag = value[compiled[index]]

			if type(flag) ~= "boolean" then
				error(`Serdes.flags expected boolean field '{compiled[index]}', got {typeof(flag)}`)
			end
		end
	end

	local function unsafe_write(target: buffer, offset: number, value: Flags): ()
		for byte = 0, full_byte_count - 1 do
			local first = byte * 8 + 1
			local packed = 0
			local mask = 1

			for index = first, first + 7 do
				if value[compiled[index]] then
					packed += mask
				end

				mask *= 2
			end

			buffer.writeu8(target, offset + byte, packed)
		end

		if tail_bit_count ~= 0 then
			local first = full_byte_count * 8 + 1
			local packed = 0
			local mask = 1

			for index = first, count do
				if value[compiled[index]] then
					packed += mask
				end

				mask *= 2
			end

			buffer.writeu8(target, offset + full_byte_count, packed)
		end
	end

	local function write(target: buffer, offset: number, value: Flags): ()
		if type(value) ~= "table" then
			error(`Serdes.flags expected table, got {typeof(value)}`)
		end

		for byte = 0, full_byte_count - 1 do
			local first = byte * 8 + 1
			local packed = 0
			local mask = 1

			for index = first, first + 7 do
				local name = compiled[index]
				local flag = value[name]

				if type(flag) ~= "boolean" then
					error(`Serdes.flags expected boolean field '{name}', got {typeof(flag)}`)
				end

				if flag then
					packed += mask
				end

				mask *= 2
			end

			buffer.writeu8(target, offset + byte, packed)
		end

		if tail_bit_count ~= 0 then
			local first = full_byte_count * 8 + 1
			local packed = 0
			local mask = 1

			for index = first, count do
				local name = compiled[index]
				local flag = value[name]

				if type(flag) ~= "boolean" then
					error(`Serdes.flags expected boolean field '{name}', got {typeof(flag)}`)
				end

				if flag then
					packed += mask
				end

				mask *= 2
			end

			buffer.writeu8(target, offset + full_byte_count, packed)
		end
	end

	local function read(source: buffer, offset: number, output: Flags?): Flags
		local result: Flags

		if output == nil then
			result = {}
		else
			result = output
		end

		for byte = 0, full_byte_count - 1 do
			local packed = buffer.readu8(source, offset + byte)
			local first = byte * 8 + 1
			local mask = 1

			for index = first, first + 7 do
				result[compiled[index]] = bit32.band(packed, mask) ~= 0
				mask *= 2
			end
		end

		if tail_bit_count ~= 0 then
			local packed = buffer.readu8(source, offset + full_byte_count)

			if packed > tail_maximum then
				error(`Serdes.flags decoded noncanonical final byte {packed}`)
			end

			local first = full_byte_count * 8 + 1
			local mask = 1

			for index = first, count do
				result[compiled[index]] = bit32.band(packed, mask) ~= 0
				mask *= 2
			end
		end

		return result
	end

	local function unsafe_read(source: buffer, offset: number, output: Flags?): Flags
		local result: Flags

		if output == nil then
			result = {}
		else
			result = output
		end

		for byte = 0, full_byte_count - 1 do
			local packed = buffer.readu8(source, offset + byte)
			local first = byte * 8 + 1
			local mask = 1

			for index = first, first + 7 do
				result[compiled[index]] = bit32.band(packed, mask) ~= 0
				mask *= 2
			end
		end

		if tail_bit_count ~= 0 then
			local packed = buffer.readu8(source, offset + full_byte_count)
			local first = full_byte_count * 8 + 1
			local mask = 1

			for index = first, count do
				result[compiled[index]] = bit32.band(packed, mask) ~= 0
				mask *= 2
			end
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

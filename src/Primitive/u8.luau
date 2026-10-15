--!strict
--!native

local SIZE = 1
local MIN = 0
local MAX = 255

local function validate(value: number): ()
	if type(value) ~= "number" then
		error(`Serdes.u8 expected number, got {typeof(value)}`)
	end

	if value % 1 ~= 0 or value < MIN or value > MAX then
		error(`Serdes.u8 expected integer in [{MIN}, {MAX}], got {value}`)
	end
end

local function unsafe_write(target: buffer, offset: number, value: number): ()
	buffer.writeu8(target, offset, value)
end

local function write(target: buffer, offset: number, value: number): ()
	if type(value) ~= "number" then
		error(`Serdes.u8 expected number, got {typeof(value)}`)
	end

	if value % 1 ~= 0 or value < MIN or value > MAX then
		error(`Serdes.u8 expected integer in [{MIN}, {MAX}], got {value}`)
	end

	buffer.writeu8(target, offset, value)
end

local function read(source: buffer, offset: number, _output: number?): number
	return buffer.readu8(source, offset)
end

local function array_unsafe_write(target: buffer, offset: number, values: { number }, count: number): ()
	local grouped_count = count - count % 4
	local index = 1
	local write_offset = offset

	while index <= grouped_count do
		local a = values[index]
		local b = values[index + 1]
		local c = values[index + 2]
		local d = values[index + 3]

		buffer.writeu32(target, write_offset, a + b * 0x100 + c * 0x10000 + d * 0x1000000)

		index += 4
		write_offset += 4
	end

	while index <= count do
		buffer.writeu8(target, write_offset, values[index])
		index += 1
		write_offset += 1
	end
end

local function array_write(target: buffer, offset: number, values: { number }, count: number): ()
	local grouped_count = count - count % 4
	local index = 1
	local write_offset = offset

	while index <= grouped_count do
		local a = values[index]
		local b = values[index + 1]
		local c = values[index + 2]
		local d = values[index + 3]

		if type(a) ~= "number" or a % 1 ~= 0 or a < MIN or a > MAX then
			error(`Serdes.u8 array received invalid value at index {index}`)
		end

		if type(b) ~= "number" or b % 1 ~= 0 or b < MIN or b > MAX then
			error(`Serdes.u8 array received invalid value at index {index + 1}`)
		end

		if type(c) ~= "number" or c % 1 ~= 0 or c < MIN or c > MAX then
			error(`Serdes.u8 array received invalid value at index {index + 2}`)
		end

		if type(d) ~= "number" or d % 1 ~= 0 or d < MIN or d > MAX then
			error(`Serdes.u8 array received invalid value at index {index + 3}`)
		end

		buffer.writeu32(target, write_offset, a + b * 0x100 + c * 0x10000 + d * 0x1000000)

		index += 4
		write_offset += 4
	end

	while index <= count do
		local value = values[index]

		if type(value) ~= "number" or value % 1 ~= 0 or value < MIN or value > MAX then
			error(`Serdes.u8 array received invalid value at index {index}`)
		end

		buffer.writeu8(target, write_offset, value)
		index += 1
		write_offset += 1
	end
end

local function array_read(source: buffer, offset: number, count: number, output: { number }?): { number }
	local result: {number} = if output == nil then table.create(count) :: {number} else output
	local grouped_count = count - count % 4
	local index = 1
	local read_offset = offset

	while index <= grouped_count do
		local word = buffer.readu32(source, read_offset)

		result[index] = bit32.extract(word, 0, 8)
		result[index + 1] = bit32.extract(word, 8, 8)
		result[index + 2] = bit32.extract(word, 16, 8)
		result[index + 3] = bit32.extract(word, 24, 8)

		index += 4
		read_offset += 4
	end

	while index <= count do
		result[index] = buffer.readu8(source, read_offset)
		index += 1
		read_offset += 1
	end

	return result
end

local function array_validate(values: {number}, count: number): ()
	for index = 1, count do
		local value = values[index]
		if type(value) ~= "number" or value % 1 ~= 0 or value < 0 or value > 255 then
			error(`Serdes.u8 received invalid array value at index {index}: {value}`)
		end
	end
end

return table.freeze({
	size = SIZE,
	delta_safe = true, key_safe = true,

	validate = validate,
	unsafe_write = unsafe_write,
	write = write,
	unsafe_write_fresh = unsafe_write,
	write_fresh = write,
	read = read,
	unsafe_read = read,

	array_unsafe_write = array_unsafe_write,
	array_write = array_write,
	array_validate = array_validate,
	array_unsafe_write_fresh = array_unsafe_write,
	array_write_fresh = array_write,
	array_read = array_read,
	array_unsafe_read = array_read,
})

--!strict
--!native

local SIZE = 2
local MIN = 0
local MAX = 65_535

local function validate(value: number): ()
	if type(value) ~= "number" then
		error(`Serdes.u16 expected number, got {typeof(value)}`)
	end

	if value % 1 ~= 0 or value < MIN or value > MAX then
		error(`Serdes.u16 expected integer in [{MIN}, {MAX}], got {value}`)
	end
end

local function unsafe_write(target: buffer, offset: number, value: number): ()
	buffer.writeu16(target, offset, value)
end

local function write(target: buffer, offset: number, value: number): ()
	if type(value) ~= "number" then
		error(`Serdes.u16 expected number, got {typeof(value)}`)
	end

	if value % 1 ~= 0 or value < MIN or value > MAX then
		error(`Serdes.u16 expected integer in [{MIN}, {MAX}], got {value}`)
	end

	buffer.writeu16(target, offset, value)
end

local function read(source: buffer, offset: number, _output: number?): number
	return buffer.readu16(source, offset)
end

local function array_unsafe_write(target: buffer, offset: number, values: { number }, count: number): ()
	local grouped_count = count - count % 2
	local index = 1
	local write_offset = offset

	while index <= grouped_count do
		buffer.writeu32(target, write_offset, values[index] + values[index + 1] * 0x10000)
		index += 2
		write_offset += 4
	end

	if index <= count then
		buffer.writeu16(target, write_offset, values[index])
	end
end

local function array_write(target: buffer, offset: number, values: { number }, count: number): ()
	local grouped_count = count - count % 2
	local index = 1
	local write_offset = offset

	while index <= grouped_count do
		local a = values[index]
		local b = values[index + 1]

		if type(a) ~= "number" or a % 1 ~= 0 or a < MIN or a > MAX then
			error(`Serdes.u16 array received invalid value at index {index}`)
		end

		if type(b) ~= "number" or b % 1 ~= 0 or b < MIN or b > MAX then
			error(`Serdes.u16 array received invalid value at index {index + 1}`)
		end

		buffer.writeu32(target, write_offset, a + b * 0x10000)
		index += 2
		write_offset += 4
	end

	if index <= count then
		local value = values[index]

		if type(value) ~= "number" or value % 1 ~= 0 or value < MIN or value > MAX then
			error(`Serdes.u16 array received invalid value at index {index}`)
		end

		buffer.writeu16(target, write_offset, value)
	end
end

local function array_read(source: buffer, offset: number, count: number, output: { number }?): { number }
	local result = if output == nil then table.create(count) else output
	local grouped_count = count - count % 2
	local index = 1
	local read_offset = offset

	while index <= grouped_count do
		local word = buffer.readu32(source, read_offset)

		result[index] = bit32.extract(word, 0, 16)
		result[index + 1] = bit32.extract(word, 16, 16)

		index += 2
		read_offset += 4
	end

	if index <= count then
		result[index] = buffer.readu16(source, read_offset)
	end

	return result
end

return table.freeze({
	size = SIZE,
	delta_safe = true,

	validate = validate,
	unsafe_write = unsafe_write,
	write = write,
	unsafe_write_fresh = unsafe_write,
	write_fresh = write,
	read = read,
	unsafe_read = read,

	array_unsafe_write = array_unsafe_write,
	array_write = array_write,
	array_unsafe_write_fresh = array_unsafe_write,
	array_write_fresh = array_write,
	array_read = array_read,
	array_unsafe_read = array_read,
})

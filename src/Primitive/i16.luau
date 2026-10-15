--!strict
--!native

local SIZE = 2
local MIN = -32_768
local MAX = 32_767

local function validate(value: number): ()
	if type(value) ~= "number" then
		error(`Serdes.i16 expected number, got {typeof(value)}`)
	end

	if value % 1 ~= 0 or value < MIN or value > MAX then
		error(`Serdes.i16 expected integer in [{MIN}, {MAX}], got {value}`)
	end
end

local function unsafe_write(target: buffer, offset: number, value: number): ()
	buffer.writei16(target, offset, value)
end

local function write(target: buffer, offset: number, value: number): ()
	if type(value) ~= "number" then
		error(`Serdes.i16 expected number, got {typeof(value)}`)
	end

	if value % 1 ~= 0 or value < MIN or value > MAX then
		error(`Serdes.i16 expected integer in [{MIN}, {MAX}], got {value}`)
	end

	buffer.writei16(target, offset, value)
end

local function read(source: buffer, offset: number, _output: number?): number
	return buffer.readi16(source, offset)
end

local function array_unsafe_write(target: buffer, offset: number, values: { number }, count: number): ()
	local write_offset = offset

	for index = 1, count do
		buffer.writei16(target, write_offset, values[index])
		write_offset += SIZE
	end
end

local function array_write(target: buffer, offset: number, values: { number }, count: number): ()
	local write_offset = offset

	for index = 1, count do
		local value = values[index]

		if type(value) ~= "number" or value % 1 ~= 0 or value < MIN or value > MAX then
			error(`Serdes.i16 array received invalid value at index {index}`)
		end

		buffer.writei16(target, write_offset, value)
		write_offset += SIZE
	end
end

local function array_read(source: buffer, offset: number, count: number, output: { number }?): { number }
	local result: {number} = if output == nil then table.create(count) :: {number} else output
	local read_offset = offset

	for index = 1, count do
		result[index] = buffer.readi16(source, read_offset)
		read_offset += SIZE
	end

	return result
end

local function array_validate(values: {number}, count: number): ()
	for index = 1, count do
		local value = values[index]
		if type(value) ~= "number" or value % 1 ~= 0 or value < -32768 or value > 32767 then
			error(`Serdes.i16 received invalid array value at index {index}: {value}`)
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

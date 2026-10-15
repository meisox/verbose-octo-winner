--!strict
--!native

local SIZE = 4
local MIN = 0
local MAX = 4_294_967_295

local function validate(value: number): ()
	if type(value) ~= "number" then
		error(`Serdes.u32 expected number, got {typeof(value)}`)
	end

	if value % 1 ~= 0 or value < MIN or value > MAX then
		error(`Serdes.u32 expected integer in [{MIN}, {MAX}], got {value}`)
	end
end

local function unsafe_write(target: buffer, offset: number, value: number): ()
	buffer.writeu32(target, offset, value)
end

local function write(target: buffer, offset: number, value: number): ()
	if type(value) ~= "number" then
		error(`Serdes.u32 expected number, got {typeof(value)}`)
	end

	if value % 1 ~= 0 or value < MIN or value > MAX then
		error(`Serdes.u32 expected integer in [{MIN}, {MAX}], got {value}`)
	end

	buffer.writeu32(target, offset, value)
end

local function read(source: buffer, offset: number, _output: number?): number
	return buffer.readu32(source, offset)
end

local function array_unsafe_write(target: buffer, offset: number, values: { number }, count: number): ()
	local write_offset = offset

	for index = 1, count do
		buffer.writeu32(target, write_offset, values[index])
		write_offset += SIZE
	end
end

local function array_write(target: buffer, offset: number, values: { number }, count: number): ()
	local write_offset = offset

	for index = 1, count do
		local value = values[index]

		if type(value) ~= "number" or value % 1 ~= 0 or value < MIN or value > MAX then
			error(`Serdes.u32 array received invalid value at index {index}`)
		end

		buffer.writeu32(target, write_offset, value)
		write_offset += SIZE
	end
end

local function array_read(source: buffer, offset: number, count: number, output: { number }?): { number }
	local result: {number} = if output == nil then table.create(count) :: {number} else output
	local read_offset = offset

	for index = 1, count do
		result[index] = buffer.readu32(source, read_offset)
		read_offset += SIZE
	end

	return result
end

local function array_validate(values: {number}, count: number): ()
	for index = 1, count do
		local value = values[index]
		if type(value) ~= "number" or value % 1 ~= 0 or value < 0 or value > 4294967295 then
			error(`Serdes.u32 received invalid array value at index {index}: {value}`)
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

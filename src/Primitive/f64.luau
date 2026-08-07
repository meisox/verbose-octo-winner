--!strict
--!native

local SIZE = 8

local function validate(value: number): ()
	if type(value) ~= "number" then
		error(`Serdes.f64 expected number, got {typeof(value)}`)
	end

	if not math.isfinite(value) then
		error(`Serdes.f64 expected finite number, got {value}`)
	end
end

local function unsafe_write(target: buffer, offset: number, value: number): ()
	buffer.writef64(target, offset, value)
end

local function write(target: buffer, offset: number, value: number): ()
	if type(value) ~= "number" then
		error(`Serdes.f64 expected number, got {typeof(value)}`)
	end

	if not math.isfinite(value) then
		error(`Serdes.f64 expected finite number, got {value}`)
	end

	buffer.writef64(target, offset, value)
end

local function read(source: buffer, offset: number, _output: number?): number
	local value = buffer.readf64(source, offset)

	if not math.isfinite(value) then
		error(`Serdes.f64 decoded non-finite value {value}`)
	end

	return value
end

local function unsafe_read(source: buffer, offset: number, _output: number?): number
	return buffer.readf64(source, offset)
end

local function array_unsafe_write(target: buffer, offset: number, values: { number }, count: number): ()
	local write_offset = offset

	for index = 1, count do
		buffer.writef64(target, write_offset, values[index])
		write_offset += SIZE
	end
end

local function array_write(target: buffer, offset: number, values: { number }, count: number): ()
	local write_offset = offset

	for index = 1, count do
		local value = values[index]

		if type(value) ~= "number" or not math.isfinite(value) then
			error(`Serdes.f64 array received invalid value at index {index}`)
		end

		buffer.writef64(target, write_offset, value)
		write_offset += SIZE
	end
end

local function array_read(source: buffer, offset: number, count: number, output: { number }?): { number }
	local result = if output == nil then table.create(count) else output
	local read_offset = offset

	for index = 1, count do
		local value = buffer.readf64(source, read_offset)

		if not math.isfinite(value) then
			error(`Serdes.f64 array decoded non-finite value at index {index}`)
		end

		result[index] = value
		read_offset += SIZE
	end

	return result
end

local function array_unsafe_read(source: buffer, offset: number, count: number, output: { number }?): { number }
	local result = if output == nil then table.create(count) else output
	local read_offset = offset

	for index = 1, count do
		result[index] = buffer.readf64(source, read_offset)
		read_offset += SIZE
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
	unsafe_read = unsafe_read,

	array_unsafe_write = array_unsafe_write,
	array_write = array_write,
	array_unsafe_write_fresh = array_unsafe_write,
	array_write_fresh = array_write,
	array_read = array_read,
	array_unsafe_read = array_unsafe_read,
})

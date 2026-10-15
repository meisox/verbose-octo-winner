--!strict
--!native

local SIZE = 1

local function validate(value: boolean): ()
	if type(value) ~= "boolean" then
		error(`Serdes.bool expected boolean, got {typeof(value)}`)
	end
end

local function unsafe_write(target: buffer, offset: number, value: boolean): ()
	buffer.writeu8(target, offset, if value then 1 else 0)
end

local function write(target: buffer, offset: number, value: boolean): ()
	if type(value) ~= "boolean" then
		error(`Serdes.bool expected boolean, got {typeof(value)}`)
	end

	buffer.writeu8(target, offset, if value then 1 else 0)
end

local function read(source: buffer, offset: number, _output: boolean?): boolean
	local encoded = buffer.readu8(source, offset)

	if encoded > 1 then
		error(`Serdes.bool decoded invalid byte {encoded}; expected 0 or 1`)
	end

	return encoded == 1
end

local function unsafe_read(source: buffer, offset: number, _output: boolean?): boolean
	return buffer.readu8(source, offset) ~= 0
end

local function unsafe_pack(value: boolean): number
	return if value then 1 else 0
end

local function pack(value: boolean): number
	if type(value) ~= "boolean" then
		error(`Serdes.bool expected boolean, got {typeof(value)}`)
	end

	return if value then 1 else 0
end

local function unpack(value: number): boolean
	return value ~= 0
end

local function array_unsafe_write(target: buffer, offset: number, values: { boolean }, count: number): ()
	for index = 1, count do
		buffer.writeu8(target, offset + index - 1, if values[index] then 1 else 0)
	end
end

local function array_write(target: buffer, offset: number, values: { boolean }, count: number): ()
	for index = 1, count do
		local value = values[index]

		if type(value) ~= "boolean" then
			error(`Serdes.bool array received invalid value at index {index}`)
		end

		buffer.writeu8(target, offset + index - 1, if value then 1 else 0)
	end
end

local function array_read(source: buffer, offset: number, count: number, output: { boolean }?): { boolean }
	local result: {boolean} = if output == nil then table.create(count) :: {boolean} else output

	for index = 1, count do
		local encoded = buffer.readu8(source, offset + index - 1)

		if encoded > 1 then
			error(`Serdes.bool array decoded invalid byte at index {index}`)
		end

		result[index] = encoded == 1
	end

	return result
end

local function array_unsafe_read(source: buffer, offset: number, count: number, output: { boolean }?): { boolean }
	local result: {boolean} = if output == nil then table.create(count) :: {boolean} else output

	for index = 1, count do
		result[index] = buffer.readu8(source, offset + index - 1) ~= 0
	end

	return result
end

local function array_validate(values: {boolean}, count: number): ()
	for index = 1, count do
		local value = values[index]
		if type(value) ~= "boolean" then
			error(`Serdes.bool received invalid array value at index {index}: {value}`)
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
	unsafe_read = unsafe_read,

	bits = 1,
	unsafe_pack = unsafe_pack,
	pack = pack,
	unpack = unpack,
	unsafe_unpack = unpack,

	array_unsafe_write = array_unsafe_write,
	array_write = array_write,
	array_validate = array_validate,
	array_unsafe_write_fresh = array_unsafe_write,
	array_write_fresh = array_write,
	array_read = array_read,
	array_unsafe_read = array_unsafe_read,
})

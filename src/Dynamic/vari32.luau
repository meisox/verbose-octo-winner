--!strict
--!native

local varu32 = require("./varu32")

local MIN_I32 = -2_147_483_648
local MAX_I32 = 2_147_483_647

local function zigzag(value: number): number
	return if value >= 0 then value * 2 else -value * 2 - 1
end

local function unzigzag(value: number): number
	return if value % 2 == 0 then value / 2 else -(value + 1) / 2
end

local function measure(value: number): number
	return varu32.measure(zigzag(value))
end

local function unsafe_write(target: buffer, offset: number, value: number): number
	return varu32.unsafe_write(target, offset, zigzag(value))
end

local function write(target: buffer, offset: number, value: number): number
	if type(value) ~= "number" then
		error(`Serdes.dynamic.vari32 expected number, got {typeof(value)}`)
	end

	if value % 1 ~= 0 or value < MIN_I32 or value > MAX_I32 then
		error(`Serdes.dynamic.vari32 expected integer in [{MIN_I32}, {MAX_I32}], got {value}`)
	end

	return varu32.unsafe_write(target, offset, zigzag(value))
end

local function read(source: buffer, offset: number, _output: number?): (number, number)
	local value, next_offset = varu32.read(source, offset)
	return unzigzag(value), next_offset
end

local function unsafe_read(source: buffer, offset: number, _output: number?): (number, number)
	local value, next_offset = varu32.unsafe_read(source, offset)
	return unzigzag(value), next_offset
end

return table.freeze({
	measure = measure,
	unsafe_write = unsafe_write,
	write = write,
	read = read,
	unsafe_read = unsafe_read,
	value_like = true,
})

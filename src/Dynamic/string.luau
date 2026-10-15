--!strict
--!native

local Types = require("../Types")
local length = require("../Internal/length")
local check_size = require("../Internal/size")

return function(maximum: number, encoding: Types.LengthEncoding?): Types.DynamicCodec<string>
	local prefix = length(maximum, encoding)
	check_size(prefix.max_size + maximum)
	local fixed_size = prefix.fixed_size
	local measure_length, write_length = prefix.measure, prefix.write
	local read_length, unsafe_read_length = prefix.read, prefix.unsafe_read
	local unsafe_measure: (string) -> number
	local measure: (string) -> number
	if fixed_size ~= nil then
		unsafe_measure = function(value: string): number return fixed_size + #value end
		measure = function(value: string): number
			if type(value) ~= "string" then error("Serdes.dynamic.string expected string") end
			local count = #value
			if count > maximum then error(`Serdes.dynamic.string expected at most {maximum} bytes, got {count}`) end
			return fixed_size + count
		end
	else
		unsafe_measure = function(value: string): number
			local count = #value
			return measure_length(count) + count
		end
		measure = function(value: string): number
			if type(value) ~= "string" then error("Serdes.dynamic.string expected string") end
			local count = #value
			if count > maximum then error(`Serdes.dynamic.string expected at most {maximum} bytes, got {count}`) end
			return measure_length(count) + count
		end
	end
	local function unsafe_write(target: buffer, offset: number, value: string): number
		local count = #value
		local position = write_length(target, offset, count)
		buffer.writestring(target, position, value)
		return position + count
	end
	local function write(target: buffer, offset: number, value: string): number
		measure(value)
		return unsafe_write(target, offset, value)
	end
	local function read(source: buffer, offset: number, _output: string?): (string, number)
		local count, position = read_length(source, offset)
		if count > maximum then error(`Serdes.dynamic.string decoded invalid length {count}`) end
		if count == 0 then return "", position end
		return buffer.readstring(source, position, count), position + count
	end
	local function unsafe_read(source: buffer, offset: number, _output: string?): (string, number)
		local count, position = unsafe_read_length(source, offset)
		if count == 0 then return "", position end
		return buffer.readstring(source, position, count), position + count
	end
	return table.freeze({
		measure = measure, unsafe_measure = unsafe_measure,
		min_size = prefix.min_size, max_size = prefix.max_size + maximum,
		unsafe_write = unsafe_write, write = write, read = read, unsafe_read = unsafe_read,
		unsafe_write_fresh = unsafe_write,
		value_like = true, key_safe = true,
	})
end

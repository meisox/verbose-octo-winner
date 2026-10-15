--!strict
--!native

local Types = require("../Types")
local length = require("../Internal/length")
local check_size = require("../Internal/size")

return function(maximum: number, encoding: Types.LengthEncoding?): Types.DynamicCodec<buffer>
	local prefix = length(maximum, encoding)
	check_size(prefix.max_size + maximum)
	local function unsafe_measure(value: buffer): number
		local count = buffer.len(value)
		return prefix.measure(count) + count
	end
	local function measure(value: buffer): number
		if type(value) ~= "buffer" then error("Serdes.dynamic.blob expected buffer") end
		local count = buffer.len(value)
		if count > maximum then error(`Serdes.dynamic.blob expected at most {maximum} bytes, got {count}`) end
		return prefix.measure(count) + count
	end
	local function unsafe_write(target: buffer, offset: number, value: buffer): number
		local count = buffer.len(value)
		local position = prefix.write(target, offset, count)
		buffer.copy(target, position, value, 0, count)
		return position + count
	end
	local function write(target: buffer, offset: number, value: buffer): number
		measure(value)
		return unsafe_write(target, offset, value)
	end
	local function compile_reader(checked: boolean)
		local read_length = if checked then prefix.read else prefix.unsafe_read
		return function(source: buffer, offset: number, output: buffer?): (buffer, number)
			local count, position = read_length(source, offset)
			if checked and (count > maximum or count > buffer.len(source) - position) then error("Serdes.dynamic.blob invalid or truncated payload") end
			local result = if output == nil or buffer.len(output) ~= count then buffer.create(count) else output
			buffer.copy(result, 0, source, position, count)
			return result, position + count
		end
	end
	return table.freeze({
		measure = measure, unsafe_measure = unsafe_measure,
		min_size = prefix.min_size, max_size = prefix.max_size + maximum,
		write = write, unsafe_write = unsafe_write,
		unsafe_write_fresh = unsafe_write,
		read = compile_reader(true), unsafe_read = compile_reader(false),
	})
end

--!strict
--!native

local Types = require("../Types")
local varu32 = require("./varu32")
local array_count = require("../Internal/array_count")
local check_size = require("../Internal/size")

type Array<T> = Types.Array<T>
type DynamicCodec<T> = Types.DynamicCodec<T>

local MAX_U32 = 4_294_967_295

return function(maximum_count: number): DynamicCodec<Array<number>>
	if
		type(maximum_count) ~= "number"
		or not math.isfinite(maximum_count)
		or maximum_count % 1 ~= 0
		or maximum_count < 0
		or maximum_count > MAX_U32
	then
		error(`Serdes.dynamic.delta_array expected integer maximum in [0, {MAX_U32}], got {maximum_count}`)
	end

	local function unsafe_measure(values: Array<number>): number
		local count = #values
		local size = varu32.unsafe_measure(count)

		if count == 0 then
			return size
		end

		local previous = values[1]
		size += varu32.unsafe_measure(previous)

		for index = 2, count do
			local value = values[index]
			size += varu32.unsafe_measure(value - previous)
			previous = value
		end

		return size
	end

	local count_values = array_count(maximum_count, false, "dynamic.delta_array")
	local function measure(values: Array<number>): number
		local count = count_values(values)
		local size = varu32.unsafe_measure(count)
		local previous = 0
		for index = 1, count do
			local value = values[index]
			if type(value) ~= "number" or value % 1 ~= 0 or value < previous or value > MAX_U32 then
				error(`Serdes.dynamic.delta_array received invalid or decreasing value at index {index}`)
			end
			size += varu32.unsafe_measure(value - previous)
			previous = value
		end
		return check_size(size)
	end

	local function unsafe_write(target: buffer, offset: number, values: Array<number>): number
		local count = #values
		local next_offset = varu32.unsafe_write(target, offset, count)

		if count == 0 then
			return next_offset
		end

		local previous = values[1]
		next_offset = varu32.unsafe_write(target, next_offset, previous)

		for index = 2, count do
			local value = values[index]
			next_offset = varu32.unsafe_write(target, next_offset, value - previous)
			previous = value
		end

		return next_offset
	end

	local function write(target: buffer, offset: number, values: Array<number>): number
		if type(values) ~= "table" then
			error(`Serdes.dynamic.delta_array expected table, got {typeof(values)}`)
		end

		local count = #values

		if count > maximum_count then
			error(`Serdes.dynamic.delta_array expected at most {maximum_count} elements, got {count}`)
		end

		local next_offset = varu32.unsafe_write(target, offset, count)

		if count == 0 then
			return next_offset
		end

		local previous = values[1]

		if type(previous) ~= "number" or previous % 1 ~= 0 or previous < 0 or previous > MAX_U32 then
			error(`Serdes.dynamic.delta_array received invalid value at index 1`)
		end

		next_offset = varu32.unsafe_write(target, next_offset, previous)

		for index = 2, count do
			local value = values[index]

			if type(value) ~= "number" or value % 1 ~= 0 or value < previous or value > MAX_U32 then
				error(`Serdes.dynamic.delta_array received invalid value at index {index}`)
			end

			next_offset = varu32.unsafe_write(target, next_offset, value - previous)
			previous = value
		end

		return next_offset
	end

	local function read(source: buffer, offset: number, output: Array<number>?): (Array<number>, number)
		local count, next_offset = varu32.read(source, offset)

		if count > maximum_count then
			error(`Serdes.dynamic.delta_array decoded invalid count {count}`)
		end

		if count > buffer.len(source) - next_offset then error("Serdes.dynamic.delta_array truncated payload") end

		local result: Array<number> = if output == nil then table.create(math.min(count, 4096)) :: Array<number> else output
		local old_count = #result

		if count > 0 then
			local value: number
			value, next_offset = varu32.read(source, next_offset)
			result[1] = value

			for index = 2, count do
				local delta: number
				delta, next_offset = varu32.read(source, next_offset)
				value += delta

				if value > MAX_U32 then
					error("Serdes.dynamic.delta_array decoded integer overflow")
				end

				result[index] = value
			end
		end

		for index = old_count, count + 1, -1 do
			result[index] = nil :: any
		end

		return result, next_offset
	end

	local function unsafe_read(source: buffer, offset: number, output: Array<number>?): (Array<number>, number)
		local count, next_offset = varu32.unsafe_read(source, offset)
		local result: Array<number> = if output == nil then table.create(count) :: Array<number> else output
		local old_count = #result

		if count > 0 then
			local value: number
			value, next_offset = varu32.unsafe_read(source, next_offset)
			result[1] = value

			for index = 2, count do
				local delta: number
				delta, next_offset = varu32.unsafe_read(source, next_offset)
				value += delta
				result[index] = value
			end
		end

		for index = old_count, count + 1, -1 do
			result[index] = nil :: any
		end

		return result, next_offset
	end

	return table.freeze({
		measure = measure,
		unsafe_measure = unsafe_measure,
		min_size = 1, max_size = math.min(1_073_741_824, varu32.unsafe_measure(maximum_count) + maximum_count * 5),
		unsafe_write = unsafe_write,
		unsafe_write_fresh = unsafe_write,
		write = write,
		read = read,
		unsafe_read = unsafe_read,
	})
end

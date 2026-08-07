--!strict
--!native

local Types = require("../Types")
local varu32 = require("./varu32")

type Array<T> = Types.Array<T>
type DynamicCodec<T> = Types.DynamicCodec<T>

local MAX_U32 = 4_294_967_295

return function<T>(element: DynamicCodec<T>, maximum_count: number): DynamicCodec<Array<T>>
	if element.value_like ~= true then
		error("Serdes.dynamic.rle expected a value-like element codec")
	end

	if
		type(maximum_count) ~= "number"
		or not math.isfinite(maximum_count)
		or maximum_count % 1 ~= 0
		or maximum_count < 0
		or maximum_count > MAX_U32
	then
		error(`Serdes.dynamic.rle expected integer maximum in [0, {MAX_U32}], got {maximum_count}`)
	end

	local element_measure = element.measure
	local element_unsafe_write = element.unsafe_write
	local element_write = element.write
	local element_read = element.read
	local element_unsafe_read = element.unsafe_read

	local function measure(values: Array<T>): number
		local count = #values
		local size = varu32.measure(count)
		local index = 1

		while index <= count do
			local value = values[index]
			local run_length = 1

			while index + run_length <= count and values[index + run_length] == value do
				run_length += 1
			end

			size += element_measure(value) + varu32.measure(run_length)
			index += run_length
		end

		return size
	end

	local function unsafe_write(target: buffer, offset: number, values: Array<T>): number
		local count = #values
		local next_offset = varu32.unsafe_write(target, offset, count)
		local index = 1

		while index <= count do
			local value = values[index]
			local run_length = 1

			while index + run_length <= count and values[index + run_length] == value do
				run_length += 1
			end

			next_offset = element_unsafe_write(target, next_offset, value)
			next_offset = varu32.unsafe_write(target, next_offset, run_length)
			index += run_length
		end

		return next_offset
	end

	local function write(target: buffer, offset: number, values: Array<T>): number
		if type(values) ~= "table" then
			error(`Serdes.dynamic.rle expected table, got {typeof(values)}`)
		end

		local count = #values

		if count > maximum_count then
			error(`Serdes.dynamic.rle expected at most {maximum_count} elements, got {count}`)
		end

		local next_offset = varu32.unsafe_write(target, offset, count)
		local index = 1

		while index <= count do
			local value = values[index]
			local run_length = 1

			while index + run_length <= count and values[index + run_length] == value do
				run_length += 1
			end

			next_offset = element_write(target, next_offset, value)
			next_offset = varu32.unsafe_write(target, next_offset, run_length)
			index += run_length
		end

		return next_offset
	end

	local function read(source: buffer, offset: number, output: Array<T>?): (Array<T>, number)
		local count, next_offset = varu32.read(source, offset)

		if count > maximum_count then
			error(`Serdes.dynamic.rle decoded invalid count {count}`)
		end

		local result = if output == nil then table.create(count) :: Array<T> else output
		local old_count = #result
		local produced = 0

		while produced < count do
			local value: T
			local run_length: number

			value, next_offset = element_read(source, next_offset, result[produced + 1])
			run_length, next_offset = varu32.read(source, next_offset)

			if run_length == 0 or produced + run_length > count then
				error(`Serdes.dynamic.rle decoded invalid run length {run_length}`)
			end

			for index = produced + 1, produced + run_length do
				result[index] = value
			end

			produced += run_length
		end

		for index = old_count, count + 1, -1 do
			result[index] = nil :: any
		end

		return result, next_offset
	end

	local function unsafe_read(source: buffer, offset: number, output: Array<T>?): (Array<T>, number)
		local count, next_offset = varu32.unsafe_read(source, offset)
		local result = if output == nil then table.create(count) :: Array<T> else output
		local old_count = #result
		local produced = 0

		while produced < count do
			local value: T
			local run_length: number

			value, next_offset = element_unsafe_read(source, next_offset, result[produced + 1])
			run_length, next_offset = varu32.unsafe_read(source, next_offset)

			for index = produced + 1, produced + run_length do
				result[index] = value
			end

			produced += run_length
		end

		for index = old_count, count + 1, -1 do
			result[index] = nil :: any
		end

		return result, next_offset
	end

	return table.freeze({
		measure = measure,
		unsafe_write = unsafe_write,
		write = write,
		read = read,
		unsafe_read = unsafe_read,
	})
end

--!strict
--!native

local Types = require("../Types")
local as_dynamic = require("../Internal/as_dynamic")
local length = require("../Internal/length")
local array_count = require("../Internal/array_count")
local check_size = require("../Internal/size")

return function<T>(child: Types.AnyCodec<T>, maximum: number, encoding: Types.LengthEncoding?): Types.DynamicCodec<Types.DynamicArray<T>>
	local element = as_dynamic(child)
	local prefix = length(maximum, encoding)
	local nullable = element.nullable == true
	local count_values = array_count(maximum, nullable, "dynamic.array")
	local stride = element.fixed_size
	local fixed = element.fixed_codec
	local bulk_write = if fixed then fixed.array_write else nil
	local bulk_validate = if fixed then fixed.array_validate else nil
	local bulk_unsafe_write = if fixed then fixed.array_unsafe_write else nil
	local bulk_fresh = if fixed then fixed.array_unsafe_write_fresh else nil
	local bulk_read = if fixed then fixed.array_read else nil
	local bulk_unsafe_read = if fixed then fixed.array_unsafe_read else nil
	local child_measure, child_unsafe_measure = element.measure, element.unsafe_measure
	local function unsafe_count(values: Types.DynamicArray<T>): number
		return if nullable then values.n :: number else #values
	end
	local function measure(values: Types.DynamicArray<T>): number
		local count = count_values(values)
		local size = prefix.measure(count)
		if bulk_validate then
			bulk_validate(values, count)
			return check_size(size + count * (stride :: number))
		end
		for i = 1, count do size += child_measure(values[i]) end
		return check_size(size)
	end
	local function unsafe_measure(values: Types.DynamicArray<T>): number
		local count = unsafe_count(values)
		if stride then return prefix.measure(count) + count * stride end
		local size = prefix.measure(count)
		for i = 1, count do size += child_unsafe_measure(values[i]) end
		return size
	end
	local function compile_writer(writer: (buffer, number, T) -> number, bulk: Types.ArrayWriter<T>?, checked: boolean)
		return function(target: buffer, offset: number, values: Types.DynamicArray<T>): number
			local count = if checked then count_values(values) else unsafe_count(values)
			local position = prefix.write(target, offset, count)
			if bulk then
				bulk(target, position, values, count)
				return position + count * (stride :: number)
			end
			for i = 1, count do position = writer(target, position, values[i]) end
			return position
		end
	end
	local function compile_reader(reader: (buffer, number, T?) -> (T, number), bulk: Types.ArrayReader<T>?, checked: boolean)
		local read_count = if checked then prefix.read else prefix.unsafe_read
		return function(source: buffer, offset: number, output: Types.DynamicArray<T>?): (Types.DynamicArray<T>, number)
			local count, position = read_count(source, offset)
			if checked then
				if count > maximum then error(`Serdes.dynamic.array decoded invalid count {count}`) end
				if count * element.min_size > buffer.len(source) - position then error("Serdes.dynamic.array truncated payload") end
			end
			local result: Types.DynamicArray<T> = if output == nil then table.create(math.min(count, 4096)) :: any else output
			local old_count = if nullable then result.n or #result else #result
			if bulk then
				bulk(source, position, count, result)
				position += count * (stride :: number)
			else
				for i = 1, count do result[i], position = reader(source, position, result[i]) end
			end
			for i = old_count, count + 1, -1 do result[i] = nil :: any end
			if nullable then result.n = count end
			return result, position
		end
	end
	return table.freeze({
		measure = measure, unsafe_measure = unsafe_measure,
		min_size = prefix.min_size,
		max_size = if element.max_size then math.min(1_073_741_824, prefix.max_size + maximum * element.max_size) else nil,
		unsafe_write = compile_writer(element.unsafe_write, bulk_unsafe_write, false),
		unsafe_write_fresh = compile_writer(element.unsafe_write_fresh or element.unsafe_write, bulk_fresh or bulk_unsafe_write, false),
		write = compile_writer(element.write, bulk_write, true),
		read = compile_reader(element.read, bulk_read, true),
		unsafe_read = compile_reader(element.unsafe_read, bulk_unsafe_read, false),
	})
end

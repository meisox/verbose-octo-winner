--!strict
--!native

local Types = require("../Types")
local varu32 = require("./varu32")
local as_dynamic = require("../Internal/as_dynamic")
local array_count = require("../Internal/array_count")
local length = require("../Internal/length")
local check_size = require("../Internal/size")

return function<T>(child: Types.AnyCodec<T>, maximum: number): Types.DynamicCodec<Types.DynamicArray<T>>
	local element = as_dynamic(child)
	if element.value_like ~= true then error("Serdes.dynamic.rle expected a value-like element codec") end
	length(maximum) -- Validate the configured count independently of packet data.
	local nullable = element.nullable == true
	local equivalent = element.wire_equal
	local count_values = array_count(maximum, nullable, "dynamic.rle")
	local function unsafe_count(values: Types.DynamicArray<T>): number return if nullable then values.n :: number else #values end
	local function compile_measure(measurer: (T) -> number, checked: boolean)
		return function(values: Types.DynamicArray<T>): number
			local count = if checked then count_values(values) else unsafe_count(values)
			if checked and equivalent then
				for i = 1, count do element.measure(values[i]) end
			end
			local run_measure = if checked and equivalent then element.unsafe_measure else measurer
			local size, index = varu32.unsafe_measure(count), 1
			while index <= count do
				local value = values[index]
				local run = 1
				while index + run <= count and (values[index + run] == value or (equivalent ~= nil and equivalent(value, values[index + run]))) do run += 1 end
				size += run_measure(value) + varu32.unsafe_measure(run)
				index += run
			end
			return if checked then check_size(size) else size
		end
	end
	local function compile_writer(writer: (buffer, number, T) -> number, checked: boolean)
		return function(target: buffer, offset: number, values: Types.DynamicArray<T>): number
			local equal = equivalent
			local count = if checked then count_values(values) else unsafe_count(values)
			local position = varu32.unsafe_write(target, offset, count)
			local index = 1
			while index <= count do
				local value = values[index]
				local run = 1
				while index + run <= count and (values[index + run] == value or (equal ~= nil and equal(value, values[index + run]))) do run += 1 end
				position = writer(target, position, value)
				position = varu32.unsafe_write(target, position, run)
				index += run
			end
			return position
		end
	end
	local measure = compile_measure(element.measure, true)
	local unsafe_write = compile_writer(element.unsafe_write, false)
	local write = compile_writer(element.write, true)
	if equivalent then
		write = function(target: buffer, offset: number, values: Types.DynamicArray<T>): number
			measure(values)
			return unsafe_write(target, offset, values)
		end
	end
	local function read(source: buffer, offset: number, output: Types.DynamicArray<T>?): (Types.DynamicArray<T>, number)
		local count, position = varu32.read(source, offset)
		if count > maximum then error(`Serdes.dynamic.rle decoded invalid count {count}`) end
		-- Validate every run before expanding any of them. A malformed short
		-- packet cannot cause allocation or expansion of its claimed output.
		local first_value: T? = nil
		local first_run = 0
		if count > 0 then
			first_value, position = element.read(source, position)
			first_run, position = varu32.read(source, position)
			if first_run == 0 or first_run > count then error(`Serdes.dynamic.rle invalid run length {first_run}`) end
		end
		-- A complete single run needs no staging tables. Multi-run packets
		-- retain preflight validation before their output is expanded.
		local values: {T}?, runs: {number}? = nil, nil
		local produced, slots = first_run, 0
		if produced < count then
			values, runs = {}, {first_run}
			values[1], slots = first_value :: T, 1
		end
		while produced < count do
			local value: T
			local run: number
			value, position = element.read(source, position)
			run, position = varu32.read(source, position)
			if run == 0 or run > count - produced then error(`Serdes.dynamic.rle invalid run length {run}`) end
			slots += 1
			(values :: {T})[slots], (runs :: {number})[slots] = value, run
			produced += run
		end
		local result: Types.DynamicArray<T> = if output == nil then table.create(math.min(count, 4096)) :: any else output
		local old_count = if nullable then result.n or #result else #result
		if values == nil then
			for i = 1, count do result[i] = first_value :: T end
		else
			produced = 0
			for slot = 1, slots do
				local value, run = values[slot], (runs :: {number})[slot]
				for i = produced + 1, produced + run do result[i] = value end
				produced += run
			end
		end
		for i = old_count, count + 1, -1 do result[i] = nil :: any end
		if nullable then result.n = count end
		return result, position
	end
	local function unsafe_read(source: buffer, offset: number, output: Types.DynamicArray<T>?): (Types.DynamicArray<T>, number)
		local count, position = varu32.unsafe_read(source, offset)
		local result: Types.DynamicArray<T> = if output == nil then table.create(count) :: any else output
		local old_count = if nullable then result.n or #result else #result
		local produced = 0
		while produced < count do
			local value: T
			local run: number
			value, position = element.unsafe_read(source, position)
			run, position = varu32.unsafe_read(source, position)
			if run == 0 then error("Serdes.dynamic.rle zero run would prevent progress") end
			for i = produced + 1, produced + run do result[i] = value end
			produced += run
		end
		for i = old_count, count + 1, -1 do result[i] = nil :: any end
		if nullable then result.n = count end
		return result, position
	end
	return table.freeze({
		measure = measure, unsafe_measure = compile_measure(element.unsafe_measure, false),
		min_size = 1, max_size = if element.max_size then math.min(1_073_741_824, varu32.unsafe_measure(maximum) + maximum * (element.max_size + 1)) else nil,
		write = write, unsafe_write = unsafe_write,
		unsafe_write_fresh = compile_writer(element.unsafe_write_fresh or element.unsafe_write, false),
		read = read, unsafe_read = unsafe_read,
	})
end

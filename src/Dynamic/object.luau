--!strict
--!native

local Types = require("../Types")
local schema_list = require("../Internal/schema_list")
local as_dynamic = require("../Internal/as_dynamic")
local check_size = require("../Internal/size")
type Record = {[string]: any}
type Writer = (buffer, number, any) -> number
type Reader = (buffer, number, any?) -> (any, number)

return function(fields: {Types.DynamicField<any>}): Types.DynamicCodec<Record>
	local count = schema_list(fields, "dynamic.object")
	local names = table.create(count) :: {string}
	local measurers: {(any) -> number}, unsafe_measurers: {(any) -> number} = {}, {}
	local writers: {Writer}, unsafe_writers: {Writer}, fresh_writers: {Writer} = {}, {}, {}
	local readers: {Reader}, unsafe_readers: {Reader} = {}, {}
	local seen = {}
	local minimum, maximum = 0, 0
	local bounded, static = true, true
	for i = 1, count do
		local field = fields[i]
		local name, codec = field.name, as_dynamic(field.codec)
		if type(name) ~= "string" or name == "" or seen[name] then error(`Serdes.dynamic.object invalid or duplicate field '{name}'`) end
		seen[name], names[i] = true, name
		measurers[i], unsafe_measurers[i] = codec.measure, codec.unsafe_measure
		writers[i], unsafe_writers[i] = codec.write, codec.unsafe_write
		fresh_writers[i] = codec.unsafe_write_fresh or codec.unsafe_write
		readers[i], unsafe_readers[i] = codec.read, codec.unsafe_read
		minimum += codec.min_size
		if codec.max_size then maximum += codec.max_size else bounded = false end
		static = static and codec.fixed_size ~= nil
	end
	check_size(minimum)
	local function compile_measure(selected: {(any) -> number}, checked: boolean)
		return function(value: Record): number
			if checked and type(value) ~= "table" then error("Serdes.dynamic.object expected record table") end
			local size = 0
			for i = 1, count do size += selected[i](value[names[i]]) end
			return if checked then check_size(size) else size
		end
	end
	local function compile_writer(selected: {Writer}, checked: boolean)
		return function(target: buffer, offset: number, value: Record): number
			if checked and type(value) ~= "table" then error("Serdes.dynamic.object expected record table") end
			local position = offset
			for i = 1, count do position = selected[i](target, position, value[names[i]]) end
			return position
		end
	end
	local function compile_reader(selected: {Reader})
		return function(source: buffer, offset: number, output: Record?): (Record, number)
			local result = if output == nil then {} else output
			local position = offset
			for i = 1, count do
				local name = names[i]
				result[name], position = selected[i](source, position, result[name])
			end
			return result, position
		end
	end
	return table.freeze({
		measure = compile_measure(measurers, true), unsafe_measure = compile_measure(unsafe_measurers, false),
		min_size = minimum, max_size = if bounded then math.min(maximum, 1_073_741_824) else nil,
		fixed_size = if static then minimum else nil,
		write = compile_writer(writers, true), unsafe_write = compile_writer(unsafe_writers, false),
		unsafe_write_fresh = compile_writer(fresh_writers, false),
		read = compile_reader(readers), unsafe_read = compile_reader(unsafe_readers),
	})
end

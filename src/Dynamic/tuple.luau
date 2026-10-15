--!strict
--!native

local Types = require("../Types")
local schema_list = require("../Internal/schema_list")
local as_dynamic = require("../Internal/as_dynamic")
local sequence = require("../Internal/sequence")
local check_size = require("../Internal/size")

return function(children: {Types.AnyCodec<any>}): Types.DynamicCodec<{any}>
	local count = schema_list(children, "dynamic.tuple")
	local codecs: {Types.DynamicCodec<any>} = table.create(count) :: any
	local nullable, bounded, static = false, true, true
	local minimum, maximum = 0, 0
	for i, child in children do
		local codec = as_dynamic(child)
		codecs[i] = codec
		nullable = nullable or codec.nullable == true
		minimum += codec.min_size
		if codec.max_size then maximum += codec.max_size else bounded = false end
		static = static and codec.fixed_size ~= nil
	end
	check_size(minimum)
	local validate_sequence = sequence(count, nullable, "dynamic.tuple")
	local function compile_measure(checked: boolean)
		return function(value: {any}): number
			if checked then validate_sequence(value) end
			if not checked and static then return minimum end
			local size = 0
			for i = 1, count do size += (if checked then codecs[i].measure else codecs[i].unsafe_measure)(value[i]) end
			return if checked then check_size(size) else size
		end
	end
	local function compile_writer(checked: boolean, fresh: boolean)
		local selected: {(buffer, number, any) -> number} = {}
		for i, codec in codecs do selected[i] = if checked then codec.write elseif fresh then codec.unsafe_write_fresh or codec.unsafe_write else codec.unsafe_write end
		return function(target: buffer, offset: number, value: {any}): number
			if checked then validate_sequence(value) end
			local position = offset
			for i = 1, count do position = selected[i](target, position, value[i]) end
			return position
		end
	end
	local function compile_reader(checked: boolean)
		local selected: {(buffer, number, any?) -> (any, number)} = {}
		for i, codec in codecs do selected[i] = if checked then codec.read else codec.unsafe_read end
		return function(source: buffer, offset: number, output: {any}?): ({any}, number)
			local result = if output == nil then {} else output
			local old_count, position = #result, offset
			for i = 1, count do result[i], position = selected[i](source, position, result[i]) end
			for i = old_count, count + 1, -1 do result[i] = nil end
			return result, position
		end
	end
	return table.freeze({
		measure = compile_measure(true), unsafe_measure = compile_measure(false),
		min_size = minimum, max_size = if bounded then math.min(1_073_741_824, maximum) else nil,
		fixed_size = if static then minimum else nil,
		write = compile_writer(true, false), unsafe_write = compile_writer(false, false), unsafe_write_fresh = compile_writer(false, true),
		read = compile_reader(true), unsafe_read = compile_reader(false),
	})
end

--!strict
--!native

local Types = require("../Types")
local fields = require("../Internal/fields")
local as_dynamic = require("../Internal/as_dynamic")
local enum = require("../Composite/enum")
local check_size = require("../Internal/size")
type Value = {tag: string, value: any}

return function<S>(schema: S, order: {string}?): Types.DynamicCodec<Types.Variant<S>>
	local list = fields(schema :: any, order)
	if #list == 0 then error("Serdes.dynamic.union needs at least one variant") end
	local tags: {string}, variants: {[string]: Types.DynamicCodec<any>} = {}, {}
	local minimum, maximum, bounded, static = math.huge, 0, true, true
	for i, field in list do
		local codec = as_dynamic(field.codec)
		tags[i], variants[field.name] = field.name, codec
		minimum = math.min(minimum, codec.min_size)
		if codec.max_size then maximum = math.max(maximum, codec.max_size) else bounded = false end
		static = static and codec.fixed_size ~= nil
	end
	local tag_codec = enum(tags)
	local function select(value: Value): Types.DynamicCodec<any>
		if type(value) ~= "table" or type(value.tag) ~= "string" then error("Serdes.dynamic.union expected {tag, value}") end
		local variant = variants[value.tag]
		if not variant then error(`Serdes.dynamic.union unknown tag '{value.tag}'`) end
		return variant
	end
	local function measure(value: Value): number
		return check_size(tag_codec.size + select(value).measure(value.value))
	end
	local function unsafe_measure(value: Value): number
		return tag_codec.size + variants[value.tag].unsafe_measure(value.value)
	end
	local function compile_writer(checked: boolean, fresh: boolean)
		return function(target: buffer, offset: number, value: Value): number
			local codec = if checked then select(value) else variants[value.tag]
			tag_codec.unsafe_write(target, offset, value.tag)
			local writer = if checked then codec.write elseif fresh then codec.unsafe_write_fresh or codec.unsafe_write else codec.unsafe_write
			return writer(target, offset + tag_codec.size, value.value)
		end
	end
	local function compile_reader(checked: boolean)
		local tag_read = if checked then tag_codec.read else tag_codec.unsafe_read
		return function(source: buffer, offset: number, output: Value?): (Value, number)
			local tag = tag_read(source, offset)
			local codec = variants[tag]
			local reader = if checked then codec.read else codec.unsafe_read
			local previous = if output and output.tag == tag then output.value else nil
			local value, position = reader(source, offset + tag_codec.size, previous)
			local result = if output then output else {} :: any
			result.tag, result.value = tag, value
			return result, position
		end
	end
	return table.freeze({
		measure = measure, unsafe_measure = unsafe_measure,
		min_size = tag_codec.size + minimum, max_size = if bounded then math.min(1_073_741_824, tag_codec.size + maximum) else nil,
		fixed_size = if static and minimum == maximum then tag_codec.size + minimum else nil,
		write = compile_writer(true, false), unsafe_write = compile_writer(false, false), unsafe_write_fresh = compile_writer(false, true),
		read = compile_reader(true), unsafe_read = compile_reader(false),
	}) :: any
end

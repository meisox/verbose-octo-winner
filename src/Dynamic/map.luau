--!strict
--!native

local Types = require("../Types")
local as_dynamic = require("../Internal/as_dynamic")
local length = require("../Internal/length")
local check_size = require("../Internal/size")

return function<K, V>(key_codec: Types.AnyCodec<K>, value_codec: Types.AnyCodec<V>, maximum: number, encoding: Types.LengthEncoding?): Types.DynamicCodec<{[K]: V}>
	local keys, values = as_dynamic(key_codec), as_dynamic(value_codec)
	local prefix = length(maximum, encoding)
	if keys.key_safe ~= true then error("Serdes.dynamic.map requires a lossless key codec (key_safe = true)") end
	if values.nullable then error("Serdes.dynamic.map values cannot be nullable; an absent key already represents nil") end
	local less = keys.key_less
	if less == nil and keys.fixed_codec and keys.fixed_codec.unsafe_pack then
		local pack = keys.fixed_codec.unsafe_pack
		less = function(a: K, b: K): boolean return pack(a) < pack(b) end
	end
	local function default_less(a: any, b: any): boolean
		local left, right = type(a), type(b)
		if left ~= right then return left < right end
		if left == "boolean" then return not a and b end
		return a < b
	end
	local compare = less or default_less
	local function measure(value: {[K]: V}): number
		if type(value) ~= "table" then error("Serdes.dynamic.map expected dictionary table") end
		local count, size = 0, 0
		for key, item in value do
			count += 1
			if count > maximum then error(`Serdes.dynamic.map expected at most {maximum} entries`) end
			local kind = type(key)
			if less == nil and kind ~= "number" and kind ~= "string" and kind ~= "boolean" then
				error("Serdes.dynamic.map custom key types must supply key_less")
			end
			size += keys.measure(key) + values.measure(item)
		end
		return check_size(prefix.measure(count) + size)
	end
	local function unsafe_measure(value: {[K]: V}): number
		local count, size = 0, 0
		for key, item in value do
			count += 1
			size += keys.unsafe_measure(key) + values.unsafe_measure(item)
		end
		return prefix.measure(count) + size
	end
	local function compile_writer(fresh: boolean)
		local key_write = if fresh then keys.unsafe_write_fresh or keys.unsafe_write else keys.unsafe_write
		local value_write = if fresh then values.unsafe_write_fresh or values.unsafe_write else values.unsafe_write
		return function(target: buffer, offset: number, value: {[K]: V}): number
			local sorted: {K} = {}
			for key in value do table.insert(sorted, key) end
			table.sort(sorted, compare)
			local position = prefix.write(target, offset, #sorted)
			for _, key in sorted do
				position = key_write(target, position, key)
				position = value_write(target, position, value[key])
			end
			return position
		end
	end
	local unsafe_write = compile_writer(false)
	local function write(target: buffer, offset: number, value: {[K]: V}): number
		measure(value)
		return unsafe_write(target, offset, value)
	end
	local function compile_reader(checked: boolean)
		local read_count = if checked then prefix.read else prefix.unsafe_read
		local key_read = if checked then keys.read else keys.unsafe_read
		local value_read = if checked then values.read else values.unsafe_read
		return function(source: buffer, offset: number, output: {[K]: V}?): ({[K]: V}, number)
			local count, position = read_count(source, offset)
			if checked and (count > maximum or count * (keys.min_size + values.min_size) > buffer.len(source) - position) then
				error("Serdes.dynamic.map invalid count or truncated payload")
			end
			local result: {[K]: V} = if output == nil then {} else output
			local seen: {[K]: boolean} = {}
			local previous: K? = nil
			for _ = 1, count do
				local key: K
				key, position = key_read(source, position)
				if checked and (key == nil or seen[key] or (previous ~= nil and not compare(previous, key))) then
					error("Serdes.dynamic.map keys must be unique and in canonical order")
				end
				local item: V
				item, position = value_read(source, position, result[key])
				if checked and item == nil then error("Serdes.dynamic.map decoded nil value") end
				result[key], seen[key], previous = item, true, key
			end
			for key in result do if not seen[key] then result[key] = nil :: any end end
			return result, position
		end
	end
	return table.freeze({
		measure = measure, unsafe_measure = unsafe_measure,
		min_size = prefix.min_size,
		max_size = if keys.max_size and values.max_size then math.min(1_073_741_824, prefix.max_size + maximum * (keys.max_size + values.max_size)) else nil,
		write = write, unsafe_write = unsafe_write, unsafe_write_fresh = compile_writer(true),
		read = compile_reader(true), unsafe_read = compile_reader(false),
	})
end

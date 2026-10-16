--!strict
--!native

local Types = require("../Types")
type Record = {[string]: any}

return function(names: {string}, codecs: {Types.Codec<any>}): Types.DeltaCodec<Record>
	local count = #names
	local header_size = math.ceil(count / 8)
	local sizes: {number}, masks: {number}, offsets: {number} = {}, {}, {}
	local writers: {(buffer, number, any) -> ()} = {}
	local readers: {(buffer, number, any?) -> any} = {}
	local unsafe_readers: {(buffer, number, any?) -> any} = {}
	local validators: {(any) -> ()} = {}
	local equivalents: {((any, any) -> boolean)?} = {}
	for i, codec in codecs do
		if codec.delta_safe ~= true then error(`Serdes.delta field '{names[i]}' codec is not value-like`) end
		sizes[i], masks[i], offsets[i] = codec.size, 2 ^ ((i - 1) % 8), (i - 1) // 8
		writers[i], readers[i], unsafe_readers[i], validators[i] = codec.unsafe_write_fresh, codec.read, codec.unsafe_read, codec.validate
		equivalents[i] = codec.wire_equal
	end
	local unused_mask = if count % 8 == 0 then 0 else 256 - 2 ^ (count % 8)
	local function compile_encode(checked: boolean)
		return function(baseline: Record, current: Record): buffer
			if checked and (type(baseline) ~= "table" or type(current) ~= "table") then
				error("Serdes.delta encode expected baseline and current tables")
			end
			local changed = {}
			local size = header_size
			for i = 1, count do
				local value = current[names[i]]
				if checked then validators[i](value) end
				local equal = equivalents[i]
				if value ~= baseline[names[i]] and (equal == nil or not equal(value, baseline[names[i]])) then
					table.insert(changed, i)
					size += sizes[i]
				end
			end
			local target = buffer.create(size)
			local position = header_size
			for _, i in changed do
				local offset = offsets[i]
				buffer.writeu8(target, offset, bit32.bor(buffer.readu8(target, offset), masks[i]))
				writers[i](target, position, current[names[i]])
				position += sizes[i]
			end
			return target
		end
	end
	local function decode_into(source: buffer, output: Record): Record
		if type(source) ~= "buffer" or buffer.len(source) < header_size then error("Serdes.delta truncated mask") end
		if type(output) ~= "table" or table.isfrozen(output) or getmetatable(output) ~= nil then
			error("Serdes.delta decode_into expected a plain writable baseline table")
		end
		if bit32.band(buffer.readu8(source, header_size - 1), unused_mask) ~= 0 then error("Serdes.delta invalid change mask") end
		local changed = {}
		local expected = header_size
		for i = 1, count do
			if bit32.btest(buffer.readu8(source, offsets[i]), masks[i]) then
				table.insert(changed, i)
				expected += sizes[i]
			end
		end
		if expected ~= buffer.len(source) then error(`Serdes.delta expected exactly {expected} bytes, got {buffer.len(source)}`) end
		local pending = table.create(#changed)
		local position = header_size
		for slot, i in changed do
			pending[slot] = readers[i](source, position)
			position += sizes[i]
		end
		for slot, i in changed do output[names[i]] = pending[slot] end
		return output
	end
	local function unsafe_decode_into(source: buffer, output: Record): Record
		local position = header_size
		for i = 1, count do
			if bit32.btest(buffer.readu8(source, offsets[i]), masks[i]) then
				output[names[i]] = unsafe_readers[i](source, position)
				position += sizes[i]
			end
		end
		return output
	end
	return table.freeze({
		encode = compile_encode(true), unsafe_encode = compile_encode(false),
		decode_into = decode_into, unsafe_decode_into = unsafe_decode_into,
	})
end

--!strict
--!native

local MAX_U32 = 4_294_967_295

local function unsafe_measure(value: number): number
	if value < 0x80 then
		return 1
	elseif value < 0x4000 then
		return 2
	elseif value < 0x20_0000 then
		return 3
	elseif value < 0x1000_0000 then
		return 4
	end

	return 5
end

local function measure(value: number): number
	if type(value) ~= "number" or value % 1 ~= 0 or value < 0 or value > MAX_U32 then
		error(`Serdes.dynamic.varu32 expected integer in [0, {MAX_U32}], got {value}`)
	end
	if value < 0x80 then return 1 end
	if value < 0x4000 then return 2 end
	if value < 0x20_0000 then return 3 end
	if value < 0x1000_0000 then return 4 end
	return 5
end

local function write_value(target: buffer, offset: number, value: number): number
	if value < 0x80 then
		buffer.writeu8(target, offset, value)
		return offset + 1
	elseif value < 0x4000 then
		buffer.writeu8(target, offset, value % 0x80 + 0x80)
		buffer.writeu8(target, offset + 1, value // 0x80)
		return offset + 2
	elseif value < 0x20_0000 then
		buffer.writeu8(target, offset, value % 0x80 + 0x80)
		buffer.writeu8(target, offset + 1, value // 0x80 % 0x80 + 0x80)
		buffer.writeu8(target, offset + 2, value // 0x4000)
		return offset + 3
	elseif value < 0x1000_0000 then
		buffer.writeu8(target, offset, value % 0x80 + 0x80)
		buffer.writeu8(target, offset + 1, value // 0x80 % 0x80 + 0x80)
		buffer.writeu8(target, offset + 2, value // 0x4000 % 0x80 + 0x80)
		buffer.writeu8(target, offset + 3, value // 0x20_0000)
		return offset + 4
	end

	buffer.writeu8(target, offset, value % 0x80 + 0x80)
	buffer.writeu8(target, offset + 1, value // 0x80 % 0x80 + 0x80)
	buffer.writeu8(target, offset + 2, value // 0x4000 % 0x80 + 0x80)
	buffer.writeu8(target, offset + 3, value // 0x20_0000 % 0x80 + 0x80)
	buffer.writeu8(target, offset + 4, value // 0x1000_0000)
	return offset + 5
end

local function write(target: buffer, offset: number, value: number): number
	if type(value) ~= "number" then
		error(`Serdes.dynamic.varu32 expected number, got {typeof(value)}`)
	end

	if value % 1 ~= 0 or value < 0 or value > MAX_U32 then
		error(`Serdes.dynamic.varu32 expected integer in [0, {MAX_U32}], got {value}`)
	end

	return write_value(target, offset, value)
end

local function read(source: buffer, offset: number, _output: number?): (number, number)
	local value = 0
	local multiplier = 1

	for index = 1, 5 do
		local encoded = buffer.readu8(source, offset + index - 1)
		local payload = encoded % 0x80

		if index == 5 and (encoded >= 0x80 or payload > 15) then
			error("Serdes.dynamic.varu32 decoded overflow")
		end

		value += payload * multiplier

		if encoded < 0x80 then
			if index > 1 and payload == 0 then
				error("Serdes.dynamic.varu32 decoded noncanonical value")
			end

			return value, offset + index
		end

		multiplier *= 0x80
	end

	error("Serdes.dynamic.varu32 decoded unterminated value")
end

local function unsafe_read(source: buffer, offset: number, _output: number?): (number, number)
	local value = 0
	local multiplier = 1

	for index = 1, 5 do
		local encoded = buffer.readu8(source, offset + index - 1)
		value += encoded % 0x80 * multiplier

		if encoded < 0x80 then
			return value, offset + index
		end

		multiplier *= 0x80
	end

	return value, offset + 5
end

return table.freeze({
	measure = measure,
	unsafe_measure = unsafe_measure,
	min_size = 1, max_size = 5,
	unsafe_write = write_value,
	unsafe_write_fresh = write_value,
	write = write,
	read = read,
	unsafe_read = unsafe_read,
	value_like = true, key_safe = true,
})

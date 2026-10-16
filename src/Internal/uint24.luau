--!strict
--!native

local function write(target: buffer, offset: number, value: number): ()
	buffer.writeu16(target, offset, value)
	buffer.writeu8(target, offset + 2, bit32.rshift(value, 16))
end

local function read(source: buffer, offset: number): number
	return buffer.readu16(source, offset) + buffer.readu8(source, offset + 2) * 65_536
end

return table.freeze({ write = write, read = read })

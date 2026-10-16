--!strict
--!native

local Types = require("../Types")
local varu32 = require("../Dynamic/varu32")

return function(maximum: number, encoding: Types.LengthEncoding?)
	if type(maximum) ~= "number" or maximum % 1 ~= 0 or maximum < 0 or maximum > 4_294_967_295 then
		error(`Serdes expected integer maximum in [0, 4294967295], got {maximum}`)
	end
	if encoding == "varint" then
		return {
			min_size = 1, max_size = varu32.unsafe_measure(maximum), fixed_size = nil :: number?,
			measure = varu32.unsafe_measure, write = varu32.unsafe_write,
			read = varu32.read, unsafe_read = varu32.unsafe_read,
		}
	end
	if encoding ~= nil and encoding ~= "fixed" then error(`Serdes unknown length encoding '{encoding}'`) end
	local size: number
	local write: (buffer, number, number) -> number
	local read: (buffer, number) -> (number, number)
	if maximum <= 255 then
		size = 1
		write = function(target: buffer, offset: number, value: number): number
			buffer.writeu8(target, offset, value)
			return offset + 1
		end
		read = function(source: buffer, offset: number): (number, number)
			return buffer.readu8(source, offset), offset + 1
		end
	elseif maximum <= 65535 then
		size = 2
		write = function(target: buffer, offset: number, value: number): number
			buffer.writeu16(target, offset, value)
			return offset + 2
		end
		read = function(source: buffer, offset: number): (number, number)
			return buffer.readu16(source, offset), offset + 2
		end
	elseif maximum <= 16777215 then
		size = 3
		write = function(target: buffer, offset: number, value: number): number
			buffer.writeu16(target, offset, value)
			buffer.writeu8(target, offset + 2, bit32.rshift(value, 16))
			return offset + 3
		end
		read = function(source: buffer, offset: number): (number, number)
			return buffer.readu16(source, offset) + buffer.readu8(source, offset + 2) * 65536, offset + 3
		end
	else
		size = 4
		write = function(target: buffer, offset: number, value: number): number
			buffer.writeu32(target, offset, value)
			return offset + 4
		end
		read = function(source: buffer, offset: number): (number, number)
			return buffer.readu32(source, offset), offset + 4
		end
	end
	local function measure(_value: number): number return size end
	return { min_size = size, max_size = size, fixed_size = size, measure = measure, write = write, read = read, unsafe_read = read }
end

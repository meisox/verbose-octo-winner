--!strict
--!native

local Types = require("../Types")
local quaternion = require("../Internal/quaternion")
local validate_rotation = require("../Internal/rotation")
local smallest_three = require("../Internal/smallest_three")

type Result = Types.Codec<CFrame> & {read angular_error: number}

-- Position and rotation precision are independent. angular_error is radians.
return function(position: Types.Codec<Vector3>, rotation_bits: number?): Result
	local bits = rotation_bits or 10
	if not math.isfinite(bits) or bits % 1 ~= 0 or bits < 4 or bits > 20 then
		error("Serdes.cframe rotation bits must be an integer in [4, 20]")
	end
	if type(position) ~= "table" or type(position.size) ~= "number"
		or position.size % 1 ~= 0 or position.size < 0 or position.size > 1073741816
		or type(position.validate) ~= "function" or type(position.write) ~= "function"
		or type(position.read) ~= "function" or type(position.unsafe_write) ~= "function"
		or type(position.unsafe_read) ~= "function" then
		error("Serdes.cframe expected a fixed Vector3 position codec")
	end
	local rotation_size = math.ceil((2 + 3 * bits) / 8)
	local size = position.size + rotation_size
	local padding = rotation_size * 8 - 2 - 3 * bits
	local limit = 0.7071067811865475
	local maximum = 2 ^ bits - 1
	local scale = maximum / (2 * limit)
	local step = (2 * limit) / maximum
	local checked_omitted, angular_error = smallest_three(step)
	local function validate(value: CFrame): ()
		if typeof(value) ~= "CFrame" then error("Serdes.cframe expected CFrame") end
		position.validate(value.Position)
		local _, _, _, a,b,c,d,e,f,g,h,i = value:GetComponents()
		validate_rotation(a,b,c,d,e,f,g,h,i)
	end
	local function unsafe_write(target: buffer, offset: number, value: CFrame): ()
		position.unsafe_write(target, offset, value.Position)
		local _, _, _, r00,r01,r02,r10,r11,r12,r20,r21,r22 = value:GetComponents()
		local index, a, b, c = quaternion.choose_smallest_three(
			quaternion.matrix_to_quaternion(r00,r01,r02,r10,r11,r12,r20,r21,r22))
		local start = (offset + position.size) * 8
		buffer.writebits(target, start, 2, index)
		buffer.writebits(target, start + 2, bits, math.round((a + limit) * scale))
		buffer.writebits(target, start + 2 + bits, bits, math.round((b + limit) * scale))
		buffer.writebits(target, start + 2 + 2*bits, bits, math.round((c + limit) * scale))
		if padding > 0 then buffer.writebits(target, start + 2 + 3*bits, padding, 0) end
	end
	local function write(target: buffer, offset: number, value: CFrame): ()
		validate(value)
		unsafe_write(target, offset, value)
	end
	local function compile_reader(checked: boolean)
		local read_position = if checked then position.read else position.unsafe_read
		return function(source: buffer, offset: number, _output: CFrame?): CFrame
			local p = read_position(source, offset)
			local start = (offset + position.size) * 8
			local index = buffer.readbits(source, start, 2)
			local a = buffer.readbits(source, start + 2, bits) * step - limit
			local b = buffer.readbits(source, start + 2 + bits, bits) * step - limit
			local c = buffer.readbits(source, start + 2 + 2*bits, bits) * step - limit
			local omitted: number
			if checked then
				if padding > 0 and buffer.readbits(source, start + 2 + 3*bits, padding) ~= 0 then
					error("Serdes.cframe decoded nonzero padding")
				end
				omitted = checked_omitted(a, b, c)
			else
				omitted = math.sqrt(math.max(0, 1 - (a*a + b*b + c*c)))
			end
			if index == 0 then return CFrame.new(p.X,p.Y,p.Z,omitted,a,b,c)
			elseif index == 1 then return CFrame.new(p.X,p.Y,p.Z,a,omitted,b,c)
			elseif index == 2 then return CFrame.new(p.X,p.Y,p.Z,a,b,omitted,c)
			else return CFrame.new(p.X,p.Y,p.Z,a,b,c,omitted) end
		end
	end
	return table.freeze({
		size = size, delta_safe = true, angular_error = angular_error,
		validate = validate, write = write, unsafe_write = unsafe_write,
		write_fresh = write, unsafe_write_fresh = unsafe_write,
		read = compile_reader(true), unsafe_read = compile_reader(false),
	})
end

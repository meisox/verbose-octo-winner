--!strict
--!native

local SIZE = 8

local MIN_OFFSET = -2_147_483_648
local MAX_OFFSET = 2_147_483_647

local function validate(value: UDim): ()
	if typeof(value) ~= "UDim" then
		error(`Serdes.udim_8 expected UDim, got {typeof(value)}`)
	end

	if
		not math.isfinite(value.Scale)
		or value.Offset % 1 ~= 0
		or value.Offset < MIN_OFFSET
		or value.Offset > MAX_OFFSET
	then
		error("Serdes.udim_8 received invalid components")
	end
end

local function unsafe_write(target: buffer, offset: number, value: UDim): ()
	buffer.writef32(target, offset, value.Scale)
	buffer.writei32(target, offset + 4, value.Offset)
end

local function write(target: buffer, offset: number, value: UDim): ()
	if typeof(value) ~= "UDim" then
		error(`Serdes.udim_8 expected UDim, got {typeof(value)}`)
	end

	local value_scale = value.Scale
	local value_offset = value.Offset

	if
		not math.isfinite(value_scale)
		or value_offset % 1 ~= 0
		or value_offset < MIN_OFFSET
		or value_offset > MAX_OFFSET
	then
		error("Serdes.udim_8 received invalid components")
	end

	buffer.writef32(target, offset, value_scale)
	buffer.writei32(target, offset + 4, value_offset)
end

local function read(source: buffer, offset: number, _output: UDim?): UDim
	local scale = buffer.readf32(source, offset)
	local pixel_offset = buffer.readi32(source, offset + 4)

	if not math.isfinite(scale) then
		error("Serdes.udim_8 decoded non-finite scale")
	end

	return UDim.new(scale, pixel_offset)
end

local function unsafe_read(source: buffer, offset: number, _output: UDim?): UDim
	return UDim.new(buffer.readf32(source, offset), buffer.readi32(source, offset + 4))
end

return table.freeze({
	size = SIZE,
	delta_safe = true,

	validate = validate,
	unsafe_write = unsafe_write,
	write = write,
	unsafe_write_fresh = unsafe_write,
	write_fresh = write,
	read = read,
	unsafe_read = unsafe_read,
})

--!strict
--!native

local SIZE = 3

local function validate(value: Color3): ()
	if typeof(value) ~= "Color3" then
		error(`Serdes.color3_3 expected Color3, got {typeof(value)}`)
	end

	local r = value.R
	local g = value.G
	local b = value.B

	if
		not math.isfinite(r)
		or not math.isfinite(g)
		or not math.isfinite(b)
		or r < 0
		or r > 1
		or g < 0
		or g > 1
		or b < 0
		or b > 1
	then
		error("Serdes.color3_3 expected components in [0, 1]")
	end
end

local function unsafe_write(target: buffer, offset: number, value: Color3): ()
	buffer.writeu8(target, offset, math.round(value.R * 255))
	buffer.writeu8(target, offset + 1, math.round(value.G * 255))
	buffer.writeu8(target, offset + 2, math.round(value.B * 255))
end

local function write(target: buffer, offset: number, value: Color3): ()
	if typeof(value) ~= "Color3" then
		error(`Serdes.color3_3 expected Color3, got {typeof(value)}`)
	end

	local r = value.R
	local g = value.G
	local b = value.B

	if
		not math.isfinite(r)
		or not math.isfinite(g)
		or not math.isfinite(b)
		or r < 0
		or r > 1
		or g < 0
		or g > 1
		or b < 0
		or b > 1
	then
		error("Serdes.color3_3 expected components in [0, 1]")
	end

	buffer.writeu8(target, offset, math.round(r * 255))
	buffer.writeu8(target, offset + 1, math.round(g * 255))
	buffer.writeu8(target, offset + 2, math.round(b * 255))
end

local function read(source: buffer, offset: number, _output: Color3?): Color3
	return Color3.fromRGB(
		buffer.readu8(source, offset),
		buffer.readu8(source, offset + 1),
		buffer.readu8(source, offset + 2)
	)
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
	unsafe_read = read,
})

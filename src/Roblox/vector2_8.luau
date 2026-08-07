--!strict
--!native

local SIZE = 8

local function validate(value: Vector2): ()
	if typeof(value) ~= "Vector2" then
		error(`Serdes.vector2_8 expected Vector2, got {typeof(value)}`)
	end

	if not math.isfinite(value.X) or not math.isfinite(value.Y) then
		error("Serdes.vector2_8 expected finite components")
	end
end

local function unsafe_write(target: buffer, offset: number, value: Vector2): ()
	buffer.writef32(target, offset, value.X)
	buffer.writef32(target, offset + 4, value.Y)
end

local function write(target: buffer, offset: number, value: Vector2): ()
	if typeof(value) ~= "Vector2" then
		error(`Serdes.vector2_8 expected Vector2, got {typeof(value)}`)
	end

	local x = value.X
	local y = value.Y

	if not math.isfinite(x) or not math.isfinite(y) then
		error("Serdes.vector2_8 expected finite components")
	end

	buffer.writef32(target, offset, x)
	buffer.writef32(target, offset + 4, y)
end

local function read(source: buffer, offset: number, _output: Vector2?): Vector2
	local x = buffer.readf32(source, offset)
	local y = buffer.readf32(source, offset + 4)

	if not math.isfinite(x) or not math.isfinite(y) then
		error("Serdes.vector2_8 decoded non-finite component")
	end

	return Vector2.new(x, y)
end

local function unsafe_read(source: buffer, offset: number, _output: Vector2?): Vector2
	return Vector2.new(buffer.readf32(source, offset), buffer.readf32(source, offset + 4))
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

--!strict
--!native

local SIZE = 12

local function validate(value: Vector3): ()
	if typeof(value) ~= "Vector3" then
		error(`Serdes.vector3_12 expected Vector3, got {typeof(value)}`)
	end

	if not math.isfinite(value.X) or not math.isfinite(value.Y) or not math.isfinite(value.Z) then
		error("Serdes.vector3_12 expected finite components")
	end
end

local function unsafe_write(target: buffer, offset: number, value: Vector3): ()
	buffer.writef32(target, offset, value.X)
	buffer.writef32(target, offset + 4, value.Y)
	buffer.writef32(target, offset + 8, value.Z)
end

local function write(target: buffer, offset: number, value: Vector3): ()
	if typeof(value) ~= "Vector3" then
		error(`Serdes.vector3_12 expected Vector3, got {typeof(value)}`)
	end

	local x = value.X
	local y = value.Y
	local z = value.Z

	if not math.isfinite(x) or not math.isfinite(y) or not math.isfinite(z) then
		error("Serdes.vector3_12 expected finite components")
	end

	buffer.writef32(target, offset, x)
	buffer.writef32(target, offset + 4, y)
	buffer.writef32(target, offset + 8, z)
end

local function read(source: buffer, offset: number, _output: Vector3?): Vector3
	local x = buffer.readf32(source, offset)
	local y = buffer.readf32(source, offset + 4)
	local z = buffer.readf32(source, offset + 8)

	if not math.isfinite(x) or not math.isfinite(y) or not math.isfinite(z) then
		error("Serdes.vector3_12 decoded non-finite component")
	end

	return Vector3.new(x, y, z)
end

local function unsafe_read(source: buffer, offset: number, _output: Vector3?): Vector3
	return Vector3.new(
		buffer.readf32(source, offset),
		buffer.readf32(source, offset + 4),
		buffer.readf32(source, offset + 8)
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
	unsafe_read = unsafe_read,
})

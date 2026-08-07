--!strict
--!native

local quaternion = require("../Internal/quaternion")

local matrix_to_quaternion = quaternion.matrix_to_quaternion

local SIZE = 28

local function validate(value: CFrame): ()
	if typeof(value) ~= "CFrame" then
		error(`Serdes.cframe_28 expected CFrame, got {typeof(value)}`)
	end

	local px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22 = value:GetComponents()

	if
		not math.isfinite(px)
		or not math.isfinite(py)
		or not math.isfinite(pz)
		or not math.isfinite(r00)
		or not math.isfinite(r01)
		or not math.isfinite(r02)
		or not math.isfinite(r10)
		or not math.isfinite(r11)
		or not math.isfinite(r12)
		or not math.isfinite(r20)
		or not math.isfinite(r21)
		or not math.isfinite(r22)
	then
		error("Serdes.cframe_28 expected finite components")
	end
end

local function unsafe_write(target: buffer, offset: number, value: CFrame): ()
	local px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22 = value:GetComponents()
	local qx, qy, qz, qw = matrix_to_quaternion(r00, r01, r02, r10, r11, r12, r20, r21, r22)

	if qw < 0 then
		qx = -qx
		qy = -qy
		qz = -qz
		qw = -qw
	end

	buffer.writef32(target, offset, px)
	buffer.writef32(target, offset + 4, py)
	buffer.writef32(target, offset + 8, pz)

	buffer.writef32(target, offset + 12, qx)
	buffer.writef32(target, offset + 16, qy)
	buffer.writef32(target, offset + 20, qz)
	buffer.writef32(target, offset + 24, qw)
end

local function write(target: buffer, offset: number, value: CFrame): ()
	if typeof(value) ~= "CFrame" then
		error(`Serdes.cframe_28 expected CFrame, got {typeof(value)}`)
	end

	local px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22 = value:GetComponents()

	if
		not math.isfinite(px)
		or not math.isfinite(py)
		or not math.isfinite(pz)
		or not math.isfinite(r00)
		or not math.isfinite(r01)
		or not math.isfinite(r02)
		or not math.isfinite(r10)
		or not math.isfinite(r11)
		or not math.isfinite(r12)
		or not math.isfinite(r20)
		or not math.isfinite(r21)
		or not math.isfinite(r22)
	then
		error("Serdes.cframe_28 expected finite components")
	end

	local qx, qy, qz, qw = matrix_to_quaternion(r00, r01, r02, r10, r11, r12, r20, r21, r22)

	if qw < 0 then
		qx = -qx
		qy = -qy
		qz = -qz
		qw = -qw
	end

	buffer.writef32(target, offset, px)
	buffer.writef32(target, offset + 4, py)
	buffer.writef32(target, offset + 8, pz)

	buffer.writef32(target, offset + 12, qx)
	buffer.writef32(target, offset + 16, qy)
	buffer.writef32(target, offset + 20, qz)
	buffer.writef32(target, offset + 24, qw)
end

local function read(source: buffer, offset: number, _output: CFrame?): CFrame
	local px = buffer.readf32(source, offset)
	local py = buffer.readf32(source, offset + 4)
	local pz = buffer.readf32(source, offset + 8)

	local qx = buffer.readf32(source, offset + 12)
	local qy = buffer.readf32(source, offset + 16)
	local qz = buffer.readf32(source, offset + 20)
	local qw = buffer.readf32(source, offset + 24)

	if
		not math.isfinite(px)
		or not math.isfinite(py)
		or not math.isfinite(pz)
		or not math.isfinite(qx)
		or not math.isfinite(qy)
		or not math.isfinite(qz)
		or not math.isfinite(qw)
	then
		error("Serdes.cframe_28 decoded non-finite component")
	end

	local length_squared = qx * qx + qy * qy + qz * qz + qw * qw

	if not math.isfinite(length_squared) or length_squared <= 0 or qw < 0 then
		error("Serdes.cframe_28 decoded invalid quaternion")
	end

	return CFrame.new(px, py, pz, qx, qy, qz, qw)
end

local function unsafe_read(source: buffer, offset: number, _output: CFrame?): CFrame
	return CFrame.new(
		buffer.readf32(source, offset),
		buffer.readf32(source, offset + 4),
		buffer.readf32(source, offset + 8),
		buffer.readf32(source, offset + 12),
		buffer.readf32(source, offset + 16),
		buffer.readf32(source, offset + 20),
		buffer.readf32(source, offset + 24)
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

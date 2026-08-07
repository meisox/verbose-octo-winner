--!strict
--!native

local SIZE = 48

local function validate(value: CFrame): ()
	if typeof(value) ~= "CFrame" then
		error(`Serdes.cframe_48 expected CFrame, got {typeof(value)}`)
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
		error("Serdes.cframe_48 expected finite components")
	end
end

local function unsafe_write(target: buffer, offset: number, value: CFrame): ()
	local px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22 = value:GetComponents()

	buffer.writef32(target, offset, px)
	buffer.writef32(target, offset + 4, py)
	buffer.writef32(target, offset + 8, pz)
	buffer.writef32(target, offset + 12, r00)
	buffer.writef32(target, offset + 16, r01)
	buffer.writef32(target, offset + 20, r02)
	buffer.writef32(target, offset + 24, r10)
	buffer.writef32(target, offset + 28, r11)
	buffer.writef32(target, offset + 32, r12)
	buffer.writef32(target, offset + 36, r20)
	buffer.writef32(target, offset + 40, r21)
	buffer.writef32(target, offset + 44, r22)
end

local function write(target: buffer, offset: number, value: CFrame): ()
	if typeof(value) ~= "CFrame" then
		error(`Serdes.cframe_48 expected CFrame, got {typeof(value)}`)
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
		error("Serdes.cframe_48 expected finite components")
	end

	buffer.writef32(target, offset, px)
	buffer.writef32(target, offset + 4, py)
	buffer.writef32(target, offset + 8, pz)
	buffer.writef32(target, offset + 12, r00)
	buffer.writef32(target, offset + 16, r01)
	buffer.writef32(target, offset + 20, r02)
	buffer.writef32(target, offset + 24, r10)
	buffer.writef32(target, offset + 28, r11)
	buffer.writef32(target, offset + 32, r12)
	buffer.writef32(target, offset + 36, r20)
	buffer.writef32(target, offset + 40, r21)
	buffer.writef32(target, offset + 44, r22)
end

local function read(source: buffer, offset: number, _output: CFrame?): CFrame
	local px = buffer.readf32(source, offset)
	local py = buffer.readf32(source, offset + 4)
	local pz = buffer.readf32(source, offset + 8)
	local r00 = buffer.readf32(source, offset + 12)
	local r01 = buffer.readf32(source, offset + 16)
	local r02 = buffer.readf32(source, offset + 20)
	local r10 = buffer.readf32(source, offset + 24)
	local r11 = buffer.readf32(source, offset + 28)
	local r12 = buffer.readf32(source, offset + 32)
	local r20 = buffer.readf32(source, offset + 36)
	local r21 = buffer.readf32(source, offset + 40)
	local r22 = buffer.readf32(source, offset + 44)

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
		error("Serdes.cframe_48 decoded non-finite component")
	end

	return CFrame.new(px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22)
end

local function unsafe_read(source: buffer, offset: number, _output: CFrame?): CFrame
	return CFrame.new(
		buffer.readf32(source, offset),
		buffer.readf32(source, offset + 4),
		buffer.readf32(source, offset + 8),
		buffer.readf32(source, offset + 12),
		buffer.readf32(source, offset + 16),
		buffer.readf32(source, offset + 20),
		buffer.readf32(source, offset + 24),
		buffer.readf32(source, offset + 28),
		buffer.readf32(source, offset + 32),
		buffer.readf32(source, offset + 36),
		buffer.readf32(source, offset + 40),
		buffer.readf32(source, offset + 44)
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

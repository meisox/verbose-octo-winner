--!strict
--!native

local quaternion = require("../Internal/quaternion")

local matrix_to_quaternion = quaternion.matrix_to_quaternion
local choose_smallest_three = quaternion.choose_smallest_three

local SIZE = 12

local POSITION_MINIMUM = -100_000
local POSITION_MAXIMUM = 100_000
local POSITION_RANGE = POSITION_MAXIMUM - POSITION_MINIMUM

local POSITION_MAX = 1_048_575
local POSITION_ENCODE_SCALE = POSITION_MAX / POSITION_RANGE

local POSITION_DECODE_SCALE = POSITION_RANGE / POSITION_MAX

local INVERSE_SQRT_TWO = 0.7071067811865475

local ROTATION_MAX = 2_047
local ROTATION_ENCODE_SCALE = ROTATION_MAX / (2 * INVERSE_SQRT_TWO)

local ROTATION_DECODE_SCALE = (2 * INVERSE_SQRT_TWO) / ROTATION_MAX

local function validate(value: CFrame): ()
	if typeof(value) ~= "CFrame" then
		error(`Serdes.cframe_12 expected CFrame, got {typeof(value)}`)
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
		or px < POSITION_MINIMUM
		or px > POSITION_MAXIMUM
		or py < POSITION_MINIMUM
		or py > POSITION_MAXIMUM
		or pz < POSITION_MINIMUM
		or pz > POSITION_MAXIMUM
	then
		error(`Serdes.cframe_12 expected finite position in [{POSITION_MINIMUM}, {POSITION_MAXIMUM}]`)
	end
end

local function unsafe_write(target: buffer, offset: number, value: CFrame): ()
	local px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22 = value:GetComponents()

	local ix = math.round((px - POSITION_MINIMUM) * POSITION_ENCODE_SCALE)
	local iy = math.round((py - POSITION_MINIMUM) * POSITION_ENCODE_SCALE)
	local iz = math.round((pz - POSITION_MINIMUM) * POSITION_ENCODE_SCALE)

	local index, a, b, c = choose_smallest_three(matrix_to_quaternion(r00, r01, r02, r10, r11, r12, r20, r21, r22))

	local qa = math.round((a + INVERSE_SQRT_TWO) * ROTATION_ENCODE_SCALE)
	local qb = math.round((b + INVERSE_SQRT_TWO) * ROTATION_ENCODE_SCALE)
	local qc = math.round((c + INVERSE_SQRT_TWO) * ROTATION_ENCODE_SCALE)

	buffer.writeu32(target, offset, ix + bit32.lshift(bit32.extract(iy, 0, 12), 20))
	buffer.writeu32(
		target,
		offset + 4,
		bit32.rshift(iy, 12) + bit32.lshift(iz, 8) + bit32.lshift(index, 28) + bit32.lshift(bit32.extract(qa, 0, 2), 30)
	)
	buffer.writeu32(target, offset + 8, bit32.rshift(qa, 2) + bit32.lshift(qb, 9) + bit32.lshift(qc, 20))
end

local function write(target: buffer, offset: number, value: CFrame): ()
	if typeof(value) ~= "CFrame" then
		error(`Serdes.cframe_12 expected CFrame, got {typeof(value)}`)
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
		or px < POSITION_MINIMUM
		or px > POSITION_MAXIMUM
		or py < POSITION_MINIMUM
		or py > POSITION_MAXIMUM
		or pz < POSITION_MINIMUM
		or pz > POSITION_MAXIMUM
	then
		error(`Serdes.cframe_12 expected finite position in [{POSITION_MINIMUM}, {POSITION_MAXIMUM}]`)
	end

	local ix = math.round((px - POSITION_MINIMUM) * POSITION_ENCODE_SCALE)
	local iy = math.round((py - POSITION_MINIMUM) * POSITION_ENCODE_SCALE)
	local iz = math.round((pz - POSITION_MINIMUM) * POSITION_ENCODE_SCALE)

	local index, a, b, c = choose_smallest_three(matrix_to_quaternion(r00, r01, r02, r10, r11, r12, r20, r21, r22))

	local qa = math.round((a + INVERSE_SQRT_TWO) * ROTATION_ENCODE_SCALE)
	local qb = math.round((b + INVERSE_SQRT_TWO) * ROTATION_ENCODE_SCALE)
	local qc = math.round((c + INVERSE_SQRT_TWO) * ROTATION_ENCODE_SCALE)

	buffer.writeu32(target, offset, ix + bit32.lshift(bit32.extract(iy, 0, 12), 20))
	buffer.writeu32(
		target,
		offset + 4,
		bit32.rshift(iy, 12) + bit32.lshift(iz, 8) + bit32.lshift(index, 28) + bit32.lshift(bit32.extract(qa, 0, 2), 30)
	)
	buffer.writeu32(target, offset + 8, bit32.rshift(qa, 2) + bit32.lshift(qb, 9) + bit32.lshift(qc, 20))
end

local function read(source: buffer, offset: number, _output: CFrame?): CFrame
	local word0 = buffer.readu32(source, offset)
	local word1 = buffer.readu32(source, offset + 4)
	local word2 = buffer.readu32(source, offset + 8)

	if word2 >= 0x80000000 then
		error("Serdes.cframe_12 decoded noncanonical value")
	end

	local ix = bit32.extract(word0, 0, 20)
	local iy = bit32.rshift(word0, 20) + bit32.lshift(bit32.extract(word1, 0, 8), 12)
	local iz = bit32.extract(word1, 8, 20)

	local index = bit32.extract(word1, 28, 2)

	local a = (bit32.rshift(word1, 30) + bit32.lshift(bit32.extract(word2, 0, 9), 2)) * ROTATION_DECODE_SCALE
		- INVERSE_SQRT_TWO
	local b = bit32.extract(word2, 9, 11) * ROTATION_DECODE_SCALE - INVERSE_SQRT_TWO
	local c = bit32.extract(word2, 20, 11) * ROTATION_DECODE_SCALE - INVERSE_SQRT_TWO

	local omitted_squared = 1 - (a * a + b * b + c * c)
	local omitted = math.sqrt(math.max(0, omitted_squared))

	local px = POSITION_MINIMUM + ix * POSITION_DECODE_SCALE
	local py = POSITION_MINIMUM + iy * POSITION_DECODE_SCALE
	local pz = POSITION_MINIMUM + iz * POSITION_DECODE_SCALE

	if index == 0 then
		return CFrame.new(px, py, pz, omitted, a, b, c)
	elseif index == 1 then
		return CFrame.new(px, py, pz, a, omitted, b, c)
	elseif index == 2 then
		return CFrame.new(px, py, pz, a, b, omitted, c)
	else
		return CFrame.new(px, py, pz, a, b, c, omitted)
	end
end

local function unsafe_read(source: buffer, offset: number, _output: CFrame?): CFrame
	local word0 = buffer.readu32(source, offset)
	local word1 = buffer.readu32(source, offset + 4)
	local word2 = buffer.readu32(source, offset + 8)

	local ix = bit32.extract(word0, 0, 20)
	local iy = bit32.rshift(word0, 20) + bit32.lshift(bit32.extract(word1, 0, 8), 12)
	local iz = bit32.extract(word1, 8, 20)

	local index = bit32.extract(word1, 28, 2)

	local a = (bit32.rshift(word1, 30) + bit32.lshift(bit32.extract(word2, 0, 9), 2)) * ROTATION_DECODE_SCALE
		- INVERSE_SQRT_TWO
	local b = bit32.extract(word2, 9, 11) * ROTATION_DECODE_SCALE - INVERSE_SQRT_TWO
	local c = bit32.extract(word2, 20, 11) * ROTATION_DECODE_SCALE - INVERSE_SQRT_TWO

	local omitted_squared = 1 - (a * a + b * b + c * c)
	local omitted = math.sqrt(math.max(0, omitted_squared))

	local px = POSITION_MINIMUM + ix * POSITION_DECODE_SCALE
	local py = POSITION_MINIMUM + iy * POSITION_DECODE_SCALE
	local pz = POSITION_MINIMUM + iz * POSITION_DECODE_SCALE

	if index == 0 then
		return CFrame.new(px, py, pz, omitted, a, b, c)
	elseif index == 1 then
		return CFrame.new(px, py, pz, a, omitted, b, c)
	elseif index == 2 then
		return CFrame.new(px, py, pz, a, b, omitted, c)
	else
		return CFrame.new(px, py, pz, a, b, c, omitted)
	end
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

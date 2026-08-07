--!strict
--!native

local SIZE = 8

local MINIMUM = -100_000
local MAXIMUM = 100_000
local RANGE = MAXIMUM - MINIMUM

local QUANTIZED_MAX = 2_097_151

local ENCODE_SCALE = QUANTIZED_MAX / RANGE
local DECODE_SCALE = RANGE / QUANTIZED_MAX

local function validate(value: Vector3): ()
	if typeof(value) ~= "Vector3" then
		error(`Serdes.vector3_8 expected Vector3, got {typeof(value)}`)
	end

	local x = value.X
	local y = value.Y
	local z = value.Z

	if
		not math.isfinite(x)
		or not math.isfinite(y)
		or not math.isfinite(z)
		or x < MINIMUM
		or x > MAXIMUM
		or y < MINIMUM
		or y > MAXIMUM
		or z < MINIMUM
		or z > MAXIMUM
	then
		error(`Serdes.vector3_8 expected components in [{MINIMUM}, {MAXIMUM}]`)
	end
end

local function unsafe_write(target: buffer, offset: number, value: Vector3): ()
	local x = math.round((value.X - MINIMUM) * ENCODE_SCALE)
	local y = math.round((value.Y - MINIMUM) * ENCODE_SCALE)
	local z = math.round((value.Z - MINIMUM) * ENCODE_SCALE)

	buffer.writeu32(target, offset, x + bit32.lshift(bit32.extract(y, 0, 11), 21))
	buffer.writeu32(target, offset + 4, bit32.rshift(y, 11) + bit32.lshift(z, 10))
end

local function write(target: buffer, offset: number, value: Vector3): ()
	if typeof(value) ~= "Vector3" then
		error(`Serdes.vector3_8 expected Vector3, got {typeof(value)}`)
	end

	local x = value.X
	local y = value.Y
	local z = value.Z

	if
		not math.isfinite(x)
		or not math.isfinite(y)
		or not math.isfinite(z)
		or x < MINIMUM
		or x > MAXIMUM
		or y < MINIMUM
		or y > MAXIMUM
		or z < MINIMUM
		or z > MAXIMUM
	then
		error(`Serdes.vector3_8 expected components in [{MINIMUM}, {MAXIMUM}]`)
	end

	x = math.round((x - MINIMUM) * ENCODE_SCALE)
	y = math.round((y - MINIMUM) * ENCODE_SCALE)
	z = math.round((z - MINIMUM) * ENCODE_SCALE)

	buffer.writeu32(target, offset, x + bit32.lshift(bit32.extract(y, 0, 11), 21))
	buffer.writeu32(target, offset + 4, bit32.rshift(y, 11) + bit32.lshift(z, 10))
end

local function read(source: buffer, offset: number, _output: Vector3?): Vector3
	local word0 = buffer.readu32(source, offset)
	local word1 = buffer.readu32(source, offset + 4)

	if word1 >= 0x80000000 then
		error("Serdes.vector3_8 decoded noncanonical value")
	end

	local x = bit32.extract(word0, 0, 21)
	local y = bit32.rshift(word0, 21) + bit32.lshift(bit32.extract(word1, 0, 10), 11)
	local z = bit32.extract(word1, 10, 21)

	return Vector3.new(MINIMUM + x * DECODE_SCALE, MINIMUM + y * DECODE_SCALE, MINIMUM + z * DECODE_SCALE)
end

local function unsafe_read(source: buffer, offset: number, _output: Vector3?): Vector3
	local word0 = buffer.readu32(source, offset)
	local word1 = buffer.readu32(source, offset + 4)

	local x = bit32.extract(word0, 0, 21)
	local y = bit32.rshift(word0, 21) + bit32.lshift(bit32.extract(word1, 0, 10), 11)
	local z = bit32.extract(word1, 10, 21)

	return Vector3.new(MINIMUM + x * DECODE_SCALE, MINIMUM + y * DECODE_SCALE, MINIMUM + z * DECODE_SCALE)
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

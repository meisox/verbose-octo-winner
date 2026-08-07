--!strict
--!native

local SIZE = 5

local MINIMUM = -100_000
local MAXIMUM = 100_000
local RANGE = MAXIMUM - MINIMUM

local QUANTIZED_MAX = 1_048_575

local ENCODE_SCALE = QUANTIZED_MAX / RANGE
local DECODE_SCALE = RANGE / QUANTIZED_MAX

local function validate(value: Vector2): ()
	if typeof(value) ~= "Vector2" then
		error(`Serdes.vector2_5 expected Vector2, got {typeof(value)}`)
	end

	local x = value.X
	local y = value.Y

	if not math.isfinite(x) or not math.isfinite(y) or x < MINIMUM or x > MAXIMUM or y < MINIMUM or y > MAXIMUM then
		error(`Serdes.vector2_5 expected components in [{MINIMUM}, {MAXIMUM}]`)
	end
end

local function unsafe_write(target: buffer, offset: number, value: Vector2): ()
	local x = math.round((value.X - MINIMUM) * ENCODE_SCALE)
	local y = math.round((value.Y - MINIMUM) * ENCODE_SCALE)

	buffer.writeu32(target, offset, x + bit32.lshift(bit32.extract(y, 0, 12), 20))
	buffer.writeu8(target, offset + 4, bit32.rshift(y, 12))
end

local function write(target: buffer, offset: number, value: Vector2): ()
	if typeof(value) ~= "Vector2" then
		error(`Serdes.vector2_5 expected Vector2, got {typeof(value)}`)
	end

	local x = value.X
	local y = value.Y

	if not math.isfinite(x) or not math.isfinite(y) or x < MINIMUM or x > MAXIMUM or y < MINIMUM or y > MAXIMUM then
		error(`Serdes.vector2_5 expected components in [{MINIMUM}, {MAXIMUM}]`)
	end

	x = math.round((x - MINIMUM) * ENCODE_SCALE)
	y = math.round((y - MINIMUM) * ENCODE_SCALE)

	buffer.writeu32(target, offset, x + bit32.lshift(bit32.extract(y, 0, 12), 20))
	buffer.writeu8(target, offset + 4, bit32.rshift(y, 12))
end

local function read(source: buffer, offset: number, _output: Vector2?): Vector2
	local word = buffer.readu32(source, offset)
	local tail = buffer.readu8(source, offset + 4)

	local x = bit32.extract(word, 0, 20)

	local y = bit32.rshift(word, 20) + bit32.lshift(tail, 12)

	return Vector2.new(MINIMUM + x * DECODE_SCALE, MINIMUM + y * DECODE_SCALE)
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

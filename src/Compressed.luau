--!strict
--!native

local Types = require("./Types")

type Codec<T> = Types.Codec<T>

local EncodingService = game:GetService("EncodingService")
local ZSTD = Enum.CompressionAlgorithm.Zstd
local DEFAULT_LEVEL = 1
local MIN_LEVEL = -7
local MAX_LEVEL = 22

local function compression_level_or_default(compression_level: number?): number
	local level = if compression_level == nil then DEFAULT_LEVEL else compression_level

	if
		type(level) ~= "number"
		or not math.isfinite(level)
		or level % 1 ~= 0
		or level < MIN_LEVEL
		or level > MAX_LEVEL
	then
		error(`Serdes.compressed expected integer compression level in [{MIN_LEVEL}, {MAX_LEVEL}], got {level}`)
	end

	return level
end

local function encode<T>(codec: Codec<T>, value: T, compression_level: number?): buffer
	local level = compression_level_or_default(compression_level)
	local source = buffer.create(codec.size)
	codec.write_fresh(source, 0, value)

	return EncodingService:CompressBuffer(source, ZSTD, level)
end

local function unsafe_encode<T>(codec: Codec<T>, value: T, compression_level: number?): buffer
	local level = compression_level_or_default(compression_level)
	local source = buffer.create(codec.size)
	codec.unsafe_write_fresh(source, 0, value)

	return EncodingService:CompressBuffer(source, ZSTD, level)
end

local function decode<T>(codec: Codec<T>, source: buffer): T
	if type(source) ~= "buffer" then
		error(`Serdes.compressed.decode expected buffer, got {typeof(source)}`)
	end

	local size = EncodingService:GetDecompressedBufferSize(source, ZSTD)

	if size ~= codec.size then
		error(`Serdes.compressed.decode expected decompressed size {codec.size}, got {tostring(size)}`)
	end

	local decompressed = EncodingService:DecompressBuffer(source, ZSTD)
	return codec.read(decompressed, 0)
end

local function unsafe_decode<T>(codec: Codec<T>, source: buffer): T
	local decompressed = EncodingService:DecompressBuffer(source, ZSTD)
	return codec.unsafe_read(decompressed, 0)
end

return table.freeze({
	encode = encode,
	unsafe_encode = unsafe_encode,
	decode = decode,
	unsafe_decode = unsafe_decode,
})

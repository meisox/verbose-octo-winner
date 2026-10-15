--!strict
--!native

local Types = require("./Types")
local check_size = require("./Internal/size")
type Schema<T> = Types.AnyCodec<T>

local cached_service: any = nil
local function service(): any
	if cached_service == nil then cached_service = game:GetService("EncodingService") end
	return cached_service
end

local function level_or_default(level: number?): number
	local result = if level == nil then 1 else level
	if type(result) ~= "number" or result % 1 ~= 0 or result < -7 or result > 22 then
		error(`Serdes.compressed expected integer compression level in [-7, 22], got {result}`)
	end
	return result
end

local function serialize<T>(codec: Schema<T>, value: T, checked: boolean): buffer
	local schema = codec :: any
	local fixed = schema.size ~= nil
	local size = if fixed then schema.size elseif checked then schema.measure(value) else schema.unsafe_measure(value)
	if checked then check_size(size) end
	local target = buffer.create(size)
	if fixed then
		(if checked then schema.write_fresh else schema.unsafe_write_fresh)(target, 0, value)
	else
		local dynamic = schema :: Types.DynamicCodec<T>
		local writer = dynamic.unsafe_write_fresh or dynamic.unsafe_write
		local written = writer(target, 0, value)
		if checked and written ~= size then error(`Serdes.compressed measured {size} bytes but wrote {written}`) end
	end
	return target
end

local function decode_limit<T>(codec: Schema<T>, maximum: number?): number
	local schema = codec :: any
	local bound = if schema.size ~= nil then schema.size else schema.max_size
	if maximum ~= nil then
		check_size(maximum)
		bound = if bound == nil then maximum else math.min(bound, maximum)
	end
	if bound == nil then error("Serdes.compressed decoding an unbounded custom codec requires maximum_size") end
	return check_size(bound)
end

local function validate_size<T>(codec: Schema<T>, size: number, maximum: number): ()
	check_size(size)
	local schema = codec :: any
	if size > maximum then error(`Serdes.compressed decompressed size {size} exceeds maximum {maximum}`) end
	if schema.size ~= nil and size ~= schema.size then
		error(`Serdes.compressed expected decompressed size {schema.size}, got {size}`)
	end
	if schema.min_size ~= nil and size < schema.min_size then error("Serdes.compressed payload is shorter than the schema minimum") end
end

local function deserialize(codec: Schema<any>, source: buffer, offset: number, output: any, checked: boolean): any
	local schema = codec :: any
	local reader = if checked then schema.read else schema.unsafe_read
	local value, position = reader(source, offset, output)
	if checked and schema.size == nil and position ~= buffer.len(source) then
		error(`Serdes.compressed expected payload ending at {position}, got {buffer.len(source)}`)
	end
	return value
end

local function decompress<T>(codec: Schema<T>, source: buffer, maximum: number?, checked: boolean): buffer
	if checked and type(source) ~= "buffer" then error("Serdes.compressed.decode expected buffer") end
	local encoding = service()
	local expected: number? = nil
	if checked then
		local bound = decode_limit(codec, maximum)
		local size = encoding:GetDecompressedBufferSize(source, Enum.CompressionAlgorithm.Zstd)
		if type(size) ~= "number" then error("Serdes.compressed invalid Zstd frame") end
		validate_size(codec, size, bound)
		expected = size
	end
	local result = encoding:DecompressBuffer(source, Enum.CompressionAlgorithm.Zstd)
	if checked and buffer.len(result) ~= expected then error("Serdes.compressed decompressed size disagrees with its frame header") end
	return result
end

local function encode<T>(codec: Schema<T>, value: T, level: number?): buffer
	local compression_level = level_or_default(level)
	return service():CompressBuffer(serialize(codec, value, true), Enum.CompressionAlgorithm.Zstd, compression_level)
end

local function unsafe_encode<T>(codec: Schema<T>, value: T, level: number?): buffer
	local compression_level = level_or_default(level)
	return service():CompressBuffer(serialize(codec, value, false), Enum.CompressionAlgorithm.Zstd, compression_level)
end

local function decode<C>(codec: C & Schema<any>, source: buffer, maximum_size: number?): Types.Infer<C>
	return deserialize(codec, decompress(codec, source, maximum_size, true), 0, nil, true)
end

local function decode_into<C>(codec: C & Schema<any>, source: buffer, output: Types.Infer<C>, maximum_size: number?): Types.Infer<C>
	return deserialize(codec, decompress(codec, source, maximum_size, true), 0, output, true)
end

local function unsafe_decode<C>(codec: C & Schema<any>, source: buffer): Types.Infer<C>
	return deserialize(codec, decompress(codec, source, nil, false), 0, nil, false)
end

local function unsafe_decode_into<C>(codec: C & Schema<any>, source: buffer, output: Types.Infer<C>): Types.Infer<C>
	return deserialize(codec, decompress(codec, source, nil, false), 0, output, false)
end

local function frame_encode<T>(codec: Schema<T>, value: T, level: number?): buffer
	local compression_level = level_or_default(level)
	local raw = serialize(codec, value, true)
	local compressed = service():CompressBuffer(raw, Enum.CompressionAlgorithm.Zstd, compression_level)
	local use_compressed = buffer.len(compressed) < buffer.len(raw)
	local payload = if use_compressed then compressed else raw
	local framed = buffer.create(check_size(1 + buffer.len(payload)))
	buffer.writeu8(framed, 0, if use_compressed then 1 else 0)
	buffer.copy(framed, 1, payload)
	return framed
end

local function frame_read(codec: Schema<any>, source: buffer, output: any, maximum_size: number?): any
	if type(source) ~= "buffer" or buffer.len(source) < 1 then error("Serdes.compressed.adaptive expected a framed buffer") end
	local marker = buffer.readu8(source, 0)
	if marker == 0 then
		validate_size(codec, buffer.len(source) - 1, decode_limit(codec, maximum_size))
		return deserialize(codec, source, 1, output, true)
	end
	if marker ~= 1 then error(`Serdes.compressed.adaptive unknown frame marker {marker}`) end
	local payload = buffer.create(buffer.len(source) - 1)
	buffer.copy(payload, 0, source, 1)
	return deserialize(codec, decompress(codec, payload, maximum_size, true), 0, output, true)
end

local function frame_decode_into<C>(codec: C & Schema<any>, source: buffer, output: Types.Infer<C>, maximum_size: number?): Types.Infer<C>
	return frame_read(codec, source, output, maximum_size)
end

local function frame_decode<C>(codec: C & Schema<any>, source: buffer, maximum_size: number?): Types.Infer<C>
	return frame_read(codec, source, nil, maximum_size)
end

return table.freeze({
	encode = encode, unsafe_encode = unsafe_encode,
	decode = decode, unsafe_decode = unsafe_decode,
	decode_into = decode_into, unsafe_decode_into = unsafe_decode_into,
	adaptive = table.freeze({encode = frame_encode, decode = frame_decode, decode_into = frame_decode_into}),
})

--!strict

export type Array<T = number> = { T }
export type Dictionary<K = string, V = number> = { [K]: V }

export type function Infer(codec)
	local function codec_reader(codec: any): any
		if codec:is("table") then return codec:readproperty(types.singleton("read")) end
		if codec:is("intersection") then
			for _, part in codec:components() do
				if part:is("table") then
					local reader = part:readproperty(types.singleton("read"))
					if reader then return reader end
				end
			end
		end
		return nil
	end
	local reader = codec_reader(codec)
	if not reader or not reader:is("function") then error("Serdes.Infer expects a codec with a read function") end
	local returns = reader:returns()
	return returns.head[1]
end

export type function Shape(schema)
	local function codec_reader(codec: any): any
		if codec:is("table") then return codec:readproperty(types.singleton("read")) end
		if codec:is("intersection") then
			for _, part in codec:components() do
				if part:is("table") then
					local reader = part:readproperty(types.singleton("read"))
					if reader then return reader end
				end
			end
		end
		return nil
	end
	if not schema:is("table") then error("Serdes.struct expects a table of named codecs") end
	if schema:readindexer() then error("Serdes.struct needs statically named fields; use object for runtime field lists") end
	local result = types.newtable()
	for name, property in schema:properties() do
		local codec = property.read
		if not codec then error("Serdes.struct fields must be codecs") end
		local reader = codec_reader(codec)
		if not reader or not reader:is("function") then error("Serdes.struct fields must have a read function") end
		result:setproperty(name, reader:returns().head[1])
	end
	return result
end

export type function Variant(schema)
	local function codec_reader(codec: any): any
		if codec:is("table") then return codec:readproperty(types.singleton("read")) end
		if codec:is("intersection") then
			for _, part in codec:components() do
				if part:is("table") then
					local reader = part:readproperty(types.singleton("read"))
					if reader then return reader end
				end
			end
		end
		return nil
	end
	if not schema:is("table") then error("Serdes.dynamic.union expects named variants") end
	if schema:readindexer() then error("Serdes.dynamic.union needs statically named variants") end
	local result = types.never
	for tag, property in schema:properties() do
		local codec = property.read
		if not codec then error("Serdes.dynamic.union variants must be codecs") end
		local reader = codec_reader(codec)
		if not reader or not reader:is("function") then error("Serdes.dynamic.union variants must have a read function") end
		local variant = types.newtable()
		variant:setproperty(types.singleton("tag"), tag)
		variant:setproperty(types.singleton("value"), reader:returns().head[1])
		result = if result:is("never") then variant else types.unionof(result, variant)
	end
	if result:is("never") then error("Serdes.dynamic.union needs at least one variant") end
	return result
end

export type ArrayWriter<T> = (target: buffer, offset: number, values: Array<T>, count: number) -> ()
export type ArrayReader<T> = (source: buffer, offset: number, count: number, output: Array<T>?) -> Array<T>
export type ArrayValidator<T> = (values: Array<T>, count: number) -> ()

export type DynamicCodec<T> = {
	read measure: (value: T) -> number,
	read unsafe_measure: (value: T) -> number,
	read min_size: number,
	read max_size: number?,
	read fixed_size: number?,
	read fixed_codec: Codec<T>?,
	read nullable: boolean?,
	read key_safe: boolean?,
	read key_less: ((T, T) -> boolean)?,
	read wire_equal: ((T, T) -> boolean)?,
	read unsafe_write: (target: buffer, offset: number, value: T) -> number,
	read unsafe_write_fresh: ((target: buffer, offset: number, value: T) -> number)?,
	read write: (target: buffer, offset: number, value: T) -> number,
	read read: (source: buffer, offset: number, output: T?) -> (T, number),
	read unsafe_read: (source: buffer, offset: number, output: T?) -> (T, number),

	read value_like: boolean?,
}

export type DynamicField<T> = {
	read name: string,
	read codec: Codec<T> | DynamicCodec<T>,
}

export type AnyCodec<T> = Codec<T> | DynamicCodec<T>
export type DynamicArray<T> = {[number]: T, n: number?}
export type LengthEncoding = "fixed" | "varint"

export type Codec<T> = {
	read size: number,
	read nullable: boolean?,
	read key_safe: boolean?,
	read key_less: ((T, T) -> boolean)?,
	read wire_equal: ((T, T) -> boolean)?,

	read validate: (value: T) -> (),
	read unsafe_write: (target: buffer, offset: number, value: T) -> (),
	read write: (target: buffer, offset: number, value: T) -> (),
	read unsafe_write_fresh: (target: buffer, offset: number, value: T) -> (),
	read write_fresh: (target: buffer, offset: number, value: T) -> (),
	read read: (source: buffer, offset: number, output: T?) -> T,
	read unsafe_read: (source: buffer, offset: number, output: T?) -> T,

	read array_unsafe_write: ArrayWriter<T>?,
	read array_validate: ArrayValidator<T>?,
	read array_write: ArrayWriter<T>?,
	read array_unsafe_write_fresh: ArrayWriter<T>?,
	read array_write_fresh: ArrayWriter<T>?,
	read array_read: ArrayReader<T>?,
	read array_unsafe_read: ArrayReader<T>?,

	read bits: number?,
	read unsafe_pack: ((value: T) -> number)?,
	read pack: ((value: T) -> number)?,
	read unpack: ((value: number) -> T)?,
	read unsafe_unpack: ((value: number) -> T)?,

	read delta_safe: boolean?,
}

export type DeltaCodec<T> = {
	read encode: (baseline: T, current: T) -> buffer,
	read unsafe_encode: (baseline: T, current: T) -> buffer,
	read decode_into: (source: buffer, output: T) -> T,
	read unsafe_decode_into: (source: buffer, output: T) -> T,
}

export type Field<T> = {
	read name: string,
	read codec: Codec<T>,
}

export type Flags = {
	[string]: boolean,
}

return table.freeze({})

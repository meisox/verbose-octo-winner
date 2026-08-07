--!strict

export type Array<T = number> = { T }
export type Dictionary<K = string, V = number> = { [K]: V }

export type ArrayWriter<T> = (target: buffer, offset: number, values: Array<T>, count: number) -> ()
export type ArrayReader<T> = (source: buffer, offset: number, count: number, output: Array<T>?) -> Array<T>

export type DynamicCodec<T> = {
	read measure: (value: T) -> number,
	read unsafe_write: (target: buffer, offset: number, value: T) -> number,
	read write: (target: buffer, offset: number, value: T) -> number,
	read read: (source: buffer, offset: number, output: T?) -> (T, number),
	read unsafe_read: (source: buffer, offset: number, output: T?) -> (T, number),

	read value_like: boolean?,
}

export type DynamicField<T> = {
	read name: string,
	read codec: DynamicCodec<T>,
}

export type Codec<T> = {
	read size: number,

	read validate: (value: T) -> (),
	read unsafe_write: (target: buffer, offset: number, value: T) -> (),
	read write: (target: buffer, offset: number, value: T) -> (),
	read unsafe_write_fresh: (target: buffer, offset: number, value: T) -> (),
	read write_fresh: (target: buffer, offset: number, value: T) -> (),
	read read: (source: buffer, offset: number, output: T?) -> T,
	read unsafe_read: (source: buffer, offset: number, output: T?) -> T,

	read array_unsafe_write: ArrayWriter<T>?,
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

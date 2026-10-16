# Serdes

A schema-based binary serialization library for Roblox Luau, built directly on Roblox buffers.

Serdes is designed for high-frequency networking, rollback and snapshot state, ECS replication, compact storage, and other workloads where predictable layout and low overhead matter. Schemas are constructed once, cache their runtime functions and metadata, and are then reused.

## Design

Serdes keeps four concerns separate:

| Profile | Purpose | Layout |
| --- | --- | --- |
| Fixed codecs | Networking and simulation hot paths | Constant size and fixed offsets |
| `Serdes.delta` | Sparse changes against a baseline | One mask bit per field plus changed fixed fields |
| `Serdes.dynamic` | Storage-oriented variable data | Sequential, measured values |
| `Serdes.compressed` | Whole-buffer storage compression | Fixed or dynamic encode followed by Zstd |

The fixed path does not pay for dynamic sizing, varints, compression, or baseline logic unless those APIs are explicitly selected.

## Installation

Serdes has no runtime dependencies. Copy `src` into a Rojo project as a ModuleScript, or build an insertable model:

```sh
rojo build default.project.json --output build/Serdes.rbxm
```

Insert that model into `ReplicatedStorage`, name it `Serdes`, and require it as below. Keep its child modules together. The model contains only library modules, with no automatically running scripts. Compression needs Roblox's `EncodingService`; other codecs load without initializing that service. Named schema inference uses Luau's new type solver. The development tool versions are pinned in `rokit.toml`.

## Quick Start

```luau
local Serdes = require('@game/ReplicatedStorage/Serdes')

local player_state = Serdes.struct({
	id = Serdes.u32,
	health = Serdes.range(0, 100),
	alive = Serdes.bool,
	position = Serdes.vector3_12,
})

local packet = Serdes.encode(player_state, {
	id = 12_345,
	health = 87,
	alive = true,
	position = Vector3.new(100, 25, -50),
})

local state = Serdes.decode(player_state, packet)
-- state.id is number, state.alive is boolean, etc.
type PlayerState = Serdes.Infer<typeof(player_state)>
```

Construct codecs outside frequently called functions. Codec construction performs schema validation and caches sizes, offsets, readers, writers, masks, and width-specific buffer functions.

## Regular and Unsafe Operations

Regular functions use the plain name, such as `write` and `read`. Validation-skipping functions use the `unsafe_` prefix, such as `unsafe_write` and `unsafe_read`. Public functions follow the same convention.

| Regular | Unsafe | Behavior |
| --- | --- | --- |
| `encode` | `unsafe_encode` | Allocate one exact fresh buffer and encode one value |
| `into` | `unsafe_into` | Encode into an existing buffer and return the next offset |
| `decode` | `unsafe_decode` | Decode a complete fixed-size buffer |
| `decode_into` | `unsafe_decode_into` | Decode while reusing an existing output value |
| `from` | `unsafe_from` | Decode at an offset and return the value and next offset |
| `from_into` | `unsafe_from_into` | Offset decoding with output reuse |

Regular fixed encoding validates and writes in one fused traversal. Regular `decode` verifies the source type, exact byte length, and codec-specific semantic constraints. Regular `into`, `from`, and `from_into` validate the entire fixed region and require a nonnegative integer offset, including for zero-byte codecs.

Unsafe operations assume the value, source type, source size, and encoded representation are valid. Roblox buffer bounds checks still apply, but Serdes checks such as finite-number validation, canonical boolean bytes, valid enum IDs, range bounds, optional markers, and unused packed bits are skipped.

Regular composite writes can modify earlier fields or elements before a later invalid value raises an error. This is observable when `into` writes into an existing buffer.

```luau
local target = buffer.create(3)
local offset = 0

offset = Serdes.into(Serdes.u16, target, offset, 500)
offset = Serdes.into(Serdes.u8, target, offset, 100)

local value
value, offset = Serdes.from(Serdes.u16, target, 0)
```

## Fresh and Reused Buffers

`encode`, `unsafe_encode`, and batch encoders allocate zero-initialized buffers and use recursively propagated fresh-writer paths.

This matters for fixed strings and optionals:

```text
fresh string       prefix + actual payload
reused string      prefix + payload + zero remaining capacity

fresh nil optional presence byte only
reused nil optional presence byte + zero child region
```

All other codecs that overwrite their complete region reuse their normal writer functions. Fresh and reused paths always produce byte-for-byte identical canonical output.

## Fixed Primitive Codecs

| Codec | Size | Domain |
| --- | ---: | --- |
| `bool` | 1 byte | `false` or `true`; standalone bytes are canonical `0` or `1` |
| `bits(n)` | 1, 2, 3, or 4 bytes | Unsigned integer requiring exactly `1..32` meaningful bits |
| `u8` | 1 byte | `0..255` |
| `i8` | 1 byte | `-128..127` |
| `u16` | 2 bytes | `0..65_535` |
| `i16` | 2 bytes | `-32_768..32_767` |
| `u32` | 4 bytes | `0..4_294_967_295` |
| `i32` | 4 bytes | `-2_147_483_648..2_147_483_647` |
| `f32` | 4 bytes | Finite single-precision number |
| `f64` | 8 bytes | Finite double-precision number |

`bits(n)` is byte-aligned on its own:

```text
bits(1..8)   1 byte
bits(9..16)  2 bytes
bits(17..24) 3 bytes
bits(25..32) 4 bytes
```

Inside `packed`, it contributes exactly `n` bits. Use it for numeric flag masks, state IDs, counters, and application-defined bitfields.

## Fixed Composite Codecs

### Objects

`struct` infers the complete record type from named codecs. Default wire order is lexicographic by field name. Supply an explicit order when the layout must be controlled:

```luau
local player = Serdes.struct({ id = Serdes.u32, alive = Serdes.bool }, { 'id', 'alive' })
type Player = Serdes.Infer<typeof(player)>
```

`packed_struct` provides the same named-schema API with bit packing. Field names must be nonempty strings. An explicit order must contain every field exactly once. These APIs require Luau's new type solver for inference and statically named schema fields. A schema annotated as `{[string]: Codec<...>}` has already erased those names; use `object` for schemas assembled at runtime. Schema lists must be dense and cannot contain holes or extra keys.

The ordered `object` API remains available. Its field list erases field name literals, so its static result is a string-keyed record; use `struct` for precise types.

```luau
local codec = Serdes.object({
	Serdes.field('tick', Serdes.u16),
	Serdes.field('position', Serdes.vector3_12),
})
```

Object field order determines the binary layout. Its size is the sum of the child sizes. Fields are byte-oriented unless a child is explicitly a packed codec.

### Tuples

```luau
local codec = Serdes.tuple({
	Serdes.u16,
	Serdes.u8,
	Serdes.vector3_12,
})

local value = { entity_id, health, position }
```

Tuples are heterogeneous fixed composites using numeric indices. They avoid string-key field lookup and have a size equal to the sum of their children.

### Fixed Arrays

```luau
local inventory = Serdes.array(Serdes.u16, 8)
```

The value must contain exactly the configured count. Size is `element.size * count`. Primitive arrays select specialized direct buffer loops at schema construction; `u8` and `u16` additionally group values into `u32` operations. Fixed arrays and tuples with optional children take their length from the schema: trailing nils are valid, and indices outside the schema are rejected. For example, `tuple({u8, optional(u8)})` accepts `{1}`.

### Fixed Strings

```luau
local username = Serdes.string(20)
```

Strings store a length prefix and a fixed-capacity payload region:

```text
capacity <= 255    u8 prefix  + capacity bytes
capacity > 255     u16 prefix + capacity bytes
maximum capacity   65_535 bytes
```

Lengths are byte lengths, not Unicode codepoint counts.

### Blobs

```luau
local state_blob = Serdes.blob(512)
```

A blob embeds a buffer of exactly the configured size. Encoding and decoding copy the complete region with `buffer.copy`; decoding reuses an output buffer only when its size matches exactly, otherwise it allocates the correct size. A blob does not compress its contents.

### Optionals

```luau
local optional_target = Serdes.optional(Serdes.u16)
```

Layout is one presence byte followed by the complete fixed child region. Size is `1 + child.size`. Regular decoding accepts only presence bytes `0` and `1`; unsafe decoding treats any nonzero byte as present.

### Ranges

```luau
local health = Serdes.range(0, 100)
```

Ranges encode `value - minimum` using the smallest standalone width capable of storing the span:

```text
span = 0            0 bytes
span <= 255         1 byte
span <= 65_535      2 bytes
span <= 16_777_215  3 bytes
otherwise          4 bytes
```

The span may not exceed the unsigned 32-bit range. A single-value range is a zero-byte constant codec.

### Enums

```luau
local state = Serdes.enum({
	'Idle',
	'Walking',
	'Running',
	'Falling',
})
```

Enum order determines zero-based wire IDs. Storage uses zero, one, two, three, or four bytes according to the largest ID. A one-value enum is a zero-byte constant codec. Regular decoding rejects unused IDs representable by the selected width.

### Named Flags

```luau
local flags = Serdes.flags({
	'grounded',
	'sprinting',
	'blocking',
})
```

Named flags use `ceil(count / 8)` bytes and decode to a dictionary of booleans. Field order determines bit order. Use `bits(n)` instead when the application already manages a numeric mask and maximum throughput is more important than named-table ergonomics.

### Quantized Numbers

```luau
local unit_value = Serdes.quantized(0, 1, 16)
```

Quantized codecs support every integer width from 1 through 32 bits. They map a finite number in the configured interval to `0..2^bits-1` and trade precision for size. Standalone storage rounds up to a whole byte; inside packed records or arrays it uses exactly the requested width. Decoding preserves exact endpoints and rejects nonzero unused high bits. Extreme finite ranges use normalized arithmetic; ordinary ranges retain specialized fast paths.

## Packed Fields

`packed` concatenates compatible finite-domain fields, using a single word for small records and native bit accesses for larger records.

```luau
local movement_state = Serdes.enum({
	'Idle',
	'Walking',
	'Running',
	'Falling',
})

local metadata = Serdes.packed({
	Serdes.field('flags', Serdes.bits(6)),
	Serdes.field('state', movement_state),
	Serdes.field('health', Serdes.range(0, 100)),
})
```

Layout is low bits first in field order:

```text
bits 0..5   flags
bits 6..7   state
bits 8..14  health

15 meaningful bits -> 2 stored bytes
```

Supported children are codecs exposing packing metadata, currently `bool`, `bits`, `range`, `enum`, and `quantized`. Records may exceed 32 bits and fields may cross byte or word boundaries. Storage selection is:

```text
0 bits       0 bytes
1..8 bits    u8
9..16 bits   u16
17..24 bits  3 bytes
25..32 bits  u32
larger       ceil(total_bits / 8) bytes
```

Zero-bit children are still reconstructed and validated during regular encoding. Regular decoding rejects unused high storage bits and impossible child states. `object` remains byte-oriented; packing is always opt-in.

`packed_array(element, count)` packs homogeneous values using the same metadata. For example, `packed_array(bool, 100)` occupies 13 bytes; `packed_array(bits(5), 100)` occupies 63. It supports output reuse, canonical zero padding, and zero-bit constant elements. Ordinary `array` retains its byte-oriented layout and specialized bulk operations.

## Roblox Datatype Codecs

| Codec | Size | Strategy |
| --- | ---: | --- |
| `color3_3` | 3 bytes | RGB quantized to three bytes |
| `color3_12` | 12 bytes | Three `f32` components |
| `vector2_5` | 5 bytes | Two lossy 20-bit components in `[-100_000, 100_000]` |
| `vector2_8` | 8 bytes | Two `f32` components |
| `vector3_8` | 8 bytes | Three lossy 21-bit components in `[-100_000, 100_000]` |
| `vector3_12` | 12 bytes | Three `f32` components |
| `quantized_vector2(max_abs, bits)` | `ceil(2*bits/8)` | Configurable symmetric precision; exact zero |
| `quantized_vector3(max_abs, bits)` | `ceil(3*bits/8)` | Configurable symmetric precision; exact zero |
| `cframe_12` | 12 bytes | Quantized position and smallest-three rotation |
| `cframe_16` | 16 bytes | `f32` position and four-byte smallest-three rotation |
| `cframe(position_codec, rotation_bits?)` | Position bytes + rotation bytes | Independent position and rotation precision |
| `cframe_28` | 28 bytes | `f32` position and unit quaternion |
| `cframe_48` | 48 bytes | `f32` position and full rotation matrix; CPU-first profile |
| `udim_8` | 8 bytes | `f32` scale and `i32` offset |
| `udim2_16` | 16 bytes | Two `UDim` layouts |

`cframe_12` positions are restricted to `[-100_000, 100_000]` per axis. `cframe_48` calls `GetComponents()` once and writes twelve direct `f32` values without quaternion conversion.

The configurable vector codecs accept `2..32` bits per axis and either a scalar extent or a matching `Vector2`/`Vector3` of per-axis positive extents. Components are rounded symmetrically within `[-max_abs, max_abs]`. Their signed representation preserves zero exactly, reserves the most negative code, and requires zero padding bits. The returned `max_abs`, `step`, and `max_error` vectors describe the actual float32 extents, approximate grid spacing, and conservative per-axis round-trip error bounds. Error bounds include output rounding and subnormal flushing; extents that become zero in the engine are rejected. Grid spacing below float32 precision can round to zero in the metadata. The older `vector2_5`/`vector3_8` retain their layouts; their unsigned grids do not represent zero exactly.

```luau
local position = Serdes.quantized_vector3(Vector3.new(2048, 512, 2048), 18)
-- Seven position bytes; roughly 0.008 studs maximum X/Z error.
local transform = Serdes.cframe(position) -- eleven bytes total
print(math.deg(transform.angular_error)) -- <= 0.276 degrees
```

`cframe` stores a two-bit omitted-component index and three quantized quaternion components. Rotation bits default to `10` and may be `4..20`; rotation storage is `ceil((2 + 3*bits)/8)` bytes. Its `angular_error` is a conservative bound in radians relative to the normalized input rotation, including an allowance for engine rounding. `cframe_16` is `cframe(vector3_12, 10)`. All quaternion-based codecs normalize converted quaternions and reject non-finite, scaled, reflected, or degenerate input matrices; near-orthonormal input tolerates floating-point drift. Checked readers reject impossible retained components, invalid unit quaternions, and unused padding. `cframe_48` preserves arbitrary finite matrices.

## Output Reuse

Table-producing fixed codecs accept an existing output through `decode_into` or `from_into`:

```luau
local state = Serdes.decode(snapshot, first_packet)

for index = 2, #packets do
	state = Serdes.decode_into(snapshot, packets[index], state)
	consume(state)
end
```

Objects, tuples, arrays, flags, packed objects, and nested reusable children are updated in place. Blobs reuse an existing buffer. Primitive values, strings, and immutable Roblox datatypes are decoded normally and assigned back.

The output must have been created by the same codec. Output shape is intentionally not validated in the hot path. Do not call `table.clear` or replace reusable nested tables between decodes.

An optional table cannot be retained across a present, nil, present sequence because the nil result removes the stored reference. Dynamic arrays and RLE arrays reuse surviving entries and remove stale trailing entries when their decoded count shrinks.

## Batch Operations

```luau
local packet = Serdes.encode_many(player_codec, players)
local decoded = Serdes.decode_many(player_codec, packet)
local reused = Serdes.decode_many_into(player_codec, next_packet, decoded)
```

Available APIs:

```text
encode_many              unsafe_encode_many
decode_many              unsafe_decode_many
decode_many_into         unsafe_decode_many_into
```

Encoding allocates one buffer of `codec.size * #values` for dense nonnullable input. For nullable element codecs, pass `table.pack(...)`; its `n` is the batch length, including trailing nils, and decoded output includes `n`. Decoding infers count from the source length, requires an exact size multiple in the regular path, and uses primitive bulk hooks when available.

Count cannot be inferred for a zero-sized codec, so all `decode_many` variants reject zero-sized codecs. A fixed-count `array` of zero-sized constants remains valid.

## Delta Encoding

`Serdes.delta` creates a separate variable-size change codec from a fixed `object` schema:

```luau
local player = Serdes.object({
	Serdes.field('health', Serdes.u8),
	Serdes.field('position', Serdes.vector3_12),
	Serdes.field('alive', Serdes.bool),
})

local player_delta = Serdes.delta(player)
local packet = player_delta.encode(baseline, current)

player_delta.decode_into(packet, baseline)
```

Layout:

```text
ceil(field_count / 8) mask bytes, low bit first
changed field payloads in schema order, with no padding
```

The mask scales with the schema: 1..8 fields use one byte, 9..16 use two, and so on. Schemas larger than 32 fields are supported. Regular encoding validates every current field, including unchanged fields, and writes only changed values. Supply a valid prior value as the baseline. Successful decoding updates that baseline and leaves unchanged fields intact.

Delta fields must be value-like codecs with meaningful and inexpensive `~=` semantics. Primitive numbers, booleans, strings, enums, supported Roblox values, quantized values, ranges, bits, and optionals of value-like children qualify. Table composites, arrays, flags dictionaries, packed tables, tuples, and blobs are rejected. Delta does not perform recursive table diffing.

Quantized numbers also compare their encoded integer codes. Two valid values in the same quantization bucket produce no delta payload. Safe encoding still validates all current values before using that equivalence.

Methods:

```text
delta.encode(baseline, current)
delta.unsafe_encode(baseline, current)
delta.decode_into(source, output)
delta.unsafe_decode_into(source, output)
```

Regular delta decoding validates unused mask bits, exact payload length, and all changed values before committing changes. A rejected packet leaves the baseline unchanged. The baseline must be a plain, writable table. Unsafe decoding applies values directly and skips these guarantees.

## Dynamic Storage Profile

Dynamic codecs are isolated under `Serdes.dynamic`. They return moving offsets. Checked encoding validates and measures the complete value before allocating, then writes it once without repeating validation. Fixed and dynamic children can be combined directly.

```luau
local stored_player = Serdes.dynamic.struct({
	id = Serdes.u32,
	name = Serdes.dynamic.string(64),
	item_ids = Serdes.dynamic.array(Serdes.dynamic.varu32, 1_000),
})

local encoded = Serdes.dynamic.encode(stored_player, value)
local decoded = Serdes.dynamic.decode(stored_player, encoded)
type StoredPlayer = Serdes.Infer<typeof(stored_player)>
```

### Dynamic Codecs

| Codec | Representation |
| --- | --- |
| `dynamic.fixed(codec)` | Adapts one fixed codec without redefining it |
| `dynamic.string(maximum_length, encoding?)` | Length prefix plus actual string bytes |
| `dynamic.blob(maximum_length, encoding?)` | Length prefix plus actual buffer bytes |
| `dynamic.array(element, maximum_count, encoding?)` | Count prefix plus fixed or dynamic elements |
| `dynamic.object(fields)` | Dynamic fields written sequentially in field order |
| `dynamic.struct(schema, order?)` | Named fields with inferred record types; sorted or explicit order |
| `dynamic.tuple(codecs)` | Ordered heterogeneous values with schema-defined count |
| `dynamic.optional(child)` | One presence byte; absent values have no child payload |
| `dynamic.union(variants, order?)` | Enum tag followed by the selected variant payload |
| `dynamic.map(key, value, maximum_count, encoding?)` | Count and canonically sorted key/value pairs |
| `dynamic.varu32` | Canonical base-128 unsigned 32-bit varint |
| `dynamic.vari32` | ZigZag signed 32-bit integer encoded as `varu32` |
| `dynamic.delta_array(maximum_count)` | Count, first absolute unsigned value, then unsigned deltas |
| `dynamic.rle(element, maximum_count)` | Decoded count followed by value/run-length pairs |

Dynamic string and array prefix widths are selected from their configured maximum:

```text
maximum <= 255       u8 prefix
maximum <= 65_535    u16 prefix
maximum <= 16_777_215  3-byte prefix
otherwise              u32 prefix
```

The optional encoding is `'fixed'` by default. Choose `'varint'` for a 1..5-byte prefix based on the actual length. For example, an empty string capped at 100,000 bytes uses three prefix bytes by default and one with `'varint'`. A 20,000-byte length uses fewer bytes with a fixed u16 prefix than a varint. Maxima and encoding choices form part of the wire schema.

Arrays of fixed primitives retain specialized bulk operations. Nullable array elements use an explicit `n` field because Lua's `#` cannot represent trailing nils:

```luau
local targets = Serdes.dynamic.array(Serdes.dynamic.optional(Serdes.u32), 100)
local values = table.pack(12, nil, 34, nil)
local packet = Serdes.dynamic.encode(targets, values)
local restored = Serdes.dynamic.decode(targets, packet)
assert(restored.n == 4)
```

Tuples take their count from the schema and do not need `n`. Empty fixed/dynamic records, tuples, and packed records are valid zero-byte schemas.

Unions infer a discriminated `{tag, value}` type. Variant tags use sorted names by default, or the supplied explicit order. A single variant needs no tag bytes:

```luau
local message = Serdes.dynamic.union({
	text = Serdes.dynamic.string(500, 'varint'),
	count = Serdes.u32,
})
local packet = Serdes.dynamic.encode(message, {tag = 'text', value = 'hello'})
```

Maps require a lossless key codec. Integers, booleans, strings, f64, ranges, and enums qualify; quantized numbers and f32 do not. Keys are sorted naturally, or by a fixed key codec's packed IDs. A custom key type must supply `key_less`. Checked decoding rejects duplicate or unsorted keys. Map values cannot be nullable; omit the key to represent absence. Output reuse removes stale keys.

`varu32` supports `0..4_294_967_295` in one to five bytes. Regular decoding rejects overflow, unterminated values, and noncanonical overlong encodings.

`vari32` supports `-2_147_483_648..2_147_483_647` using ZigZag:

```text
0 -> 0
-1 -> 1
1 -> 2
-2 -> 3
```

`dynamic.delta_array` accepts nondecreasing unsigned 32-bit values and streams deltas without allocating a transformed array. `dynamic.rle` accepts only value-like element codecs and emits runs directly. Quantized values which encode identically share a run. Checked RLE decoding validates all runs before expanding the output; a complete single run needs no staging tables. Configured maximum counts bound the permitted expanded result.

### Dynamic Operations

```text
dynamic.encode              dynamic.unsafe_encode
dynamic.decode              dynamic.unsafe_decode
dynamic.decode_into         dynamic.unsafe_decode_into
dynamic.into(codec, target, offset, value)
dynamic.from(codec, source, offset, output?)
```

Regular dynamic decode requires the entire source buffer to be consumed. `into` validates/measures before modifying the target and checks its complete region. `from` reads one value and returns its next offset. All table containers and blobs support output reuse. As with fixed codecs, a failed ordinary `read` or `decode_into` may have modified earlier children; delta decoding has the stronger atomic baseline guarantee described above.

## Whole-Buffer Compression

`Serdes.compressed` wraps fixed and dynamic codecs with whole-buffer Zstd compression through Roblox `EncodingService`. The service is loaded on first compression use:

```luau
local compressed = Serdes.compressed.encode(snapshot, value)
local decoded = Serdes.compressed.decode(snapshot, compressed)
```

```text
compressed.encode(codec, value, compression_level?)
compressed.unsafe_encode(codec, value, compression_level?)
compressed.decode(codec, source, maximum_size?)
compressed.decode_into(codec, source, output, maximum_size?)
compressed.unsafe_decode(codec, source)
compressed.unsafe_decode_into(codec, source, output)
```

The default compression level is `1`; accepted levels are integers from `-7` through `22`. Encoding first creates the complete serialized buffer, then compresses it once with `Enum.CompressionAlgorithm.Zstd`.

Regular decompression checks the reported size before decompressing. Fixed schemas require an exact match; dynamic schemas use their `max_size` bound. `maximum_size` can lower that limit and is required for an unbounded custom dynamic codec. The resulting buffer must match the frame's declared size and pass checked decoding. Unsafe decompression skips these Serdes checks. See the [Roblox EncodingService API](https://create.roblox.com/docs/reference/engine/classes/EncodingService).

`compressed.adaptive.encode`, `decode`, and `decode_into` use a distinct framed format: byte `0` followed by raw serialized data, or byte `1` followed by Zstd data. Encoding chooses compression only when it saves bytes. Total size is at most one framing byte larger than the raw serialization. Raw frames decode directly at offset one without copying the payload. Use matching adaptive APIs; the ordinary compression API continues to produce plain Zstd buffers.

Compression is intended for sufficiently large storage payloads. Small networking packets generally favor direct fixed or delta encoding because compression adds CPU work and another buffer.

## Custom Codecs

The exported fixed codec contract is:

```luau
export type Codec<T> = {
	read size: number,

	read validate: (value: T) -> (),
	read unsafe_write: (target: buffer, offset: number, value: T) -> (),
	read write: (target: buffer, offset: number, value: T) -> (),
	read unsafe_write_fresh: (target: buffer, offset: number, value: T) -> (),
	read write_fresh: (target: buffer, offset: number, value: T) -> (),
	read read: (source: buffer, offset: number, output: T?) -> T,
	read unsafe_read: (source: buffer, offset: number, output: T?) -> T,

	-- Optional bulk-array, packed-field, and delta metadata.
}
```

Writers must completely canonicalize their fixed region unless they are a fresh writer, where writes whose only purpose is zero clearing may be skipped. Regular writers should validate and write in one pass. Unsafe functions must assume valid values rather than clamp or mask them.

Custom codecs can optionally expose:

* `array_validate`, `array_unsafe_write`, `array_write`, fresh equivalents, `array_read`, and `array_unsafe_read` for specialized arrays
* `bits`, `unsafe_pack`, `pack`, `unpack`, and `unsafe_unpack` for `packed`
* `delta_safe = true` for value-like delta fields
* `nullable = true` if nil is a valid value
* `wire_equal(a, b)` to compare valid values by encoded representation for RLE/deltas
* `key_safe = true` for lossless map keys; `key_less` for custom key ordering

Dynamic codecs use:

```luau
export type DynamicCodec<T> = {
	read measure: (value: T) -> number,
	read unsafe_measure: (value: T) -> number,
	read min_size: number,
	read max_size: number?,
	read unsafe_write: (target: buffer, offset: number, value: T) -> number,
	read write: (target: buffer, offset: number, value: T) -> number,
	read read: (source: buffer, offset: number, output: T?) -> (T, number),
	read unsafe_read: (source: buffer, offset: number, output: T?) -> (T, number),

	read value_like: boolean?,
}
```

`measure` must validate the complete value and return its exact byte size. `unsafe_measure` may skip validation. Readers/writers return the first byte after the value. `min_size` must be a conservative lower bound; `max_size`, when provided, must be an upper bound. Incorrect metadata violates the custom codec contract. A dynamic codec may expose `value_like = true` for RLE, `fixed_size` for a constant-size representation, and `unsafe_write_fresh` to avoid redundant zero clearing. Inputs and custom codec behavior must remain stable throughout measurement and writing.

## Wire Compatibility and Limits

The current development revision changes layouts from commit `0327edf`: 17..24-bit standalone integers, ranges, enums, and packed records now use three bytes; fixed dynamic length prefixes also use three bytes for maxima from 65,536 through 16,777,215; delta masks use `ceil(field_count / 8)` bytes. Quantized RLE/deltas now merge equal encoded states. Existing stored data or connected clients using changed layouts need an explicit migration or protocol version. No automatic detection is attempted. See [MIGRATION.md](MIGRATION.md) for API and validation changes.

Schemas are binary protocols; Serdes does not write a schema identifier or version tag. Changing any of the following breaks compatibility:

* field or tuple order
* child codecs
* array counts
* string capacities
* enum or flag order
* range bounds
* quantization settings
* packed field order or widths

Numeric buffer operations use Roblox's little-endian buffer layout. Packed fields use the lowest bits first. Create explicit protocol versions when evolving a schema.

The only zero-byte codecs are single-value ranges, single-value enums, and composites made entirely from zero-byte children. Zero-byte values work in fixed arrays and composites, but a batch decoder cannot infer how many values are represented by an empty buffer.

Configured maxima do not override Roblox's buffer-size and available-memory limits. Compression also operates on a complete uncompressed buffer first, so it does not bypass those limits.

## Performance Guidance

* Construct schemas once and reuse them.
* Prefer fixed codecs for networking, snapshots, and simulation state.
* Use regular paths at trust boundaries and unsafe paths only for already-validated values or buffers.
* Initialize reusable state with `decode`, then update it with `decode_into`.
* Use `tuple` when numeric positions are practical and object field names are unnecessary.
* Use `packed` for several small finite fields and `bits(n)` for application-managed masks.
* Use named `flags` for ergonomics, not the hottest numeric-mask path.
* Use `encode_many` rather than constructing a temporary array codec for ad hoc batches.
* Choose CFrame precision deliberately: `cframe_12` quantizes large world positions; `cframe_16` preserves float32 position with a compact rotation; `cframe_28` preserves quaternion precision; `cframe_48` avoids conversion.
* Use `delta` when changes are sparse and a synchronized baseline already exists.
* Use the dynamic profile and compression for storage-oriented workloads, not by default on hot packet paths.
* Keep fixed string capacities and maximum dynamic counts realistic.

Generic composites perform cached indirect child calls; primitive arrays use specialized bulk loops. [BENCHMARKS.md](BENCHMARKS.md) reports paired CLI and Studio measurements, including regressions and the cost of stricter validation. No single profile is fastest and smallest for every workload.

## Development Checks

With Node.js 22+, Lune, Rojo, the Luau CLI (`luau`, `luau-analyze`), and luau-lsp available:

```sh
node scripts/test.cjs
node scripts/check-types.cjs
node scripts/benchmark.cjs
node scripts/build-studio-test.cjs
node scripts/build-studio-benchmark.cjs
```

The test runner checks positive and negative inference examples, public offset/batch APIs, malformed schemas, packing against an independent wire oracle, delta mask boundaries, dynamic composition, and quantization across floating-point extremes. Roblox tests check every datatype preset, configurable vectors across all widths, rotation precision, and invalid matrices/quaternions. Lune staging changes import paths and supplies Roblox datatype globals; compression requires engine tests. `check-types` builds a Rojo sourcemap and checks the whole package and public consumer examples against pinned engine definitions (downloaded to `build`; override with `ROBLOX_TYPES`). It requires the new solver and luau-lsp 1.70.1; `LUAU_LSP` can select a binary explicitly.

`build/StudioTests.luau` runs the current runtime suites in detached ModuleScripts and reports a source hash for that snapshot. `build/StudioBenchmark.luau` compares the original commit and working tree in the same engine process. Execute these generated runners through a Studio tool with permission to set detached ModuleScript sources; they do not depend on a particular place. CLI benchmarks save native/interpreted results to `benchmarks/results/latest.json`. GitHub Actions runs the local suites, full type checks, and Rojo model build; compression and native engine tests are separate Studio checks.

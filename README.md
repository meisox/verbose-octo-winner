# Serdes

A schema-based binary serialization library for Roblox Luau, built directly on Roblox buffers.

Serdes is designed for high-frequency networking, rollback and snapshot state, ECS replication, compact storage, and other workloads where predictable layout and low overhead matter. Schemas are constructed once, cache their runtime functions and metadata, and are then reused.

## Design

Serdes keeps four concerns separate:

| Profile | Purpose | Layout |
| --- | --- | --- |
| Fixed codecs | Networking and simulation hot paths | Constant size and fixed offsets |
| `Serdes.delta` | Sparse changes against a baseline | `u32` change mask plus changed fixed fields |
| `Serdes.dynamic` | Storage-oriented variable data | Sequential, measured values |
| `Serdes.compressed` | Whole-buffer storage compression | Fixed encode followed by Zstd |

The fixed path does not pay for dynamic sizing, varints, compression, or baseline logic unless those APIs are explicitly selected.

## Quick Start

```luau
local Serdes = require('@game/ReplicatedStorage/Serdes')

local player_state = Serdes.object({
	Serdes.field('id', Serdes.u32),
	Serdes.field('health', Serdes.range(0, 100)),
	Serdes.field('alive', Serdes.bool),
	Serdes.field('position', Serdes.vector3_8),
})

local packet = Serdes.encode(player_state, {
	id = 12_345,
	health = 87,
	alive = true,
	position = Vector3.new(100, 25, -50),
})

local state = Serdes.decode(player_state, packet)
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

Regular encoding validates and writes in one fused traversal. Regular `decode` verifies the source type, exact byte length, and codec-specific semantic constraints.

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
| `bits(n)` | 1, 2, or 4 bytes | Unsigned integer requiring exactly `1..32` meaningful bits |
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
bits(17..32) 4 bytes
```

Inside `packed`, it contributes exactly `n` bits. Use it for numeric flag masks, state IDs, counters, and application-defined bitfields.

## Fixed Composite Codecs

### Objects

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

The value must contain exactly the configured count. Size is `element.size * count`. Primitive arrays select specialized direct buffer loops at schema construction; `u8` and `u16` additionally group values into `u32` operations.

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

A blob embeds a buffer of exactly the configured size. Encoding and decoding copy the complete region with `buffer.copy`; decoding can reuse an existing output buffer. A blob does not compress its contents.

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
otherwise           4 bytes
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

Enum order determines zero-based wire IDs. Storage uses zero, one, two, or four bytes according to the largest ID. A one-value enum is a zero-byte constant codec. Regular decoding rejects unused IDs representable by the selected width.

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

Quantized codecs support 8, 16, or 32 bits. They map a finite number in the configured interval to the full unsigned integer range and trade precision for size.

## Packed Fields

`packed` combines compatible finite-domain fields into one `u8`, `u16`, or `u32` operation.

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

Supported children are codecs exposing packing metadata, currently `bool`, `bits`, `range`, `enum`, and `quantized`. Total meaningful width must be at most 32 bits. Storage selection is:

```text
0 bits       0 bytes
1..8 bits    u8
9..16 bits   u16
17..32 bits  u32
```

Zero-bit children are still reconstructed and validated during regular encoding. Regular decoding rejects unused high storage bits and impossible child states. `object` remains byte-oriented; packing is always opt-in.

## Roblox Datatype Codecs

| Codec | Size | Strategy |
| --- | ---: | --- |
| `color3_3` | 3 bytes | RGB quantized to three bytes |
| `color3_12` | 12 bytes | Three `f32` components |
| `vector2_5` | 5 bytes | Two lossy 20-bit components in `[-100_000, 100_000]` |
| `vector2_8` | 8 bytes | Two `f32` components |
| `vector3_8` | 8 bytes | Three lossy 21-bit components in `[-100_000, 100_000]` |
| `vector3_12` | 12 bytes | Three `f32` components |
| `cframe_12` | 12 bytes | Quantized position and smallest-three rotation |
| `cframe_28` | 28 bytes | `f32` position and quaternion; balanced profile |
| `cframe_48` | 48 bytes | `f32` position and full rotation matrix; CPU-first profile |
| `udim_8` | 8 bytes | `f32` scale and `i32` offset |
| `udim2_16` | 16 bytes | Two `UDim` layouts |

`cframe_12` positions are restricted to `[-100_000, 100_000]` per axis. `cframe_48` calls `GetComponents()` once and writes twelve direct `f32` values without quaternion conversion.

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

Encoding allocates one buffer of `codec.size * #values`. Decoding infers count from the source length, requires an exact size multiple in the regular path, and uses primitive bulk hooks when available.

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
u32 change mask
changed field payloads in schema order, with no padding
```

The delta schema supports at most 32 fields. Encoding makes one comparison/size pass, allocates the exact packet, writes the mask once, and fresh-writes only changed values. Decoding mutates the supplied baseline/output and leaves unchanged fields intact.

Delta fields must be value-like codecs with meaningful and inexpensive `~=` semantics. Primitive numbers, booleans, strings, enums, supported Roblox values, quantized values, ranges, bits, and optionals of value-like children qualify. Table composites, arrays, flags dictionaries, packed tables, tuples, and blobs are rejected. Delta does not perform recursive table diffing.

Methods:

```text
delta.encode(baseline, current)
delta.unsafe_encode(baseline, current)
delta.decode_into(source, output)
delta.unsafe_decode_into(source, output)
```

Regular delta decoding validates unused mask bits and requires the payload length to be consumed exactly.

## Dynamic Storage Profile

Dynamic codecs are isolated under `Serdes.dynamic`. They return moving offsets and pay a measurement pass before top-level encoding; this overhead never affects fixed codecs.

```luau
local stored_player = Serdes.dynamic.object({
	Serdes.dynamic.field('name', Serdes.dynamic.string(64)),
	Serdes.dynamic.field(
		'item_ids',
		Serdes.dynamic.array(Serdes.dynamic.varu32, 1_000)
	),
})

local encoded = Serdes.dynamic.encode(stored_player, value)
local decoded = Serdes.dynamic.decode(stored_player, encoded)
```

### Dynamic Codecs

| Codec | Representation |
| --- | --- |
| `dynamic.fixed(codec)` | Adapts one fixed codec without redefining it |
| `dynamic.string(maximum_length)` | Width-selected count prefix plus actual string bytes |
| `dynamic.array(element, maximum_count)` | Width-selected count prefix plus sequential dynamic elements |
| `dynamic.object(fields)` | Dynamic fields written sequentially in field order |
| `dynamic.varu32` | Canonical base-128 unsigned 32-bit varint |
| `dynamic.vari32` | ZigZag signed 32-bit integer encoded as `varu32` |
| `dynamic.delta_array(maximum_count)` | Count, first absolute unsigned value, then unsigned deltas |
| `dynamic.rle(element, maximum_count)` | Decoded count followed by value/run-length pairs |

Dynamic string and array prefix widths are selected from their configured maximum:

```text
maximum <= 255       u8 prefix
maximum <= 65_535    u16 prefix
otherwise            u32 prefix
```

`varu32` supports `0..4_294_967_295` in one to five bytes. Regular decoding rejects overflow, unterminated values, and noncanonical overlong encodings.

`vari32` supports `-2_147_483_648..2_147_483_647` using ZigZag:

```text
0 -> 0
-1 -> 1
1 -> 2
-2 -> 3
```

`dynamic.delta_array` accepts nondecreasing unsigned 32-bit values and streams deltas without allocating a transformed array. `dynamic.rle` accepts only value-like element codecs where `==` is cheap and meaningful; it emits runs directly without temporary run tables.

### Dynamic Operations

```text
dynamic.encode              dynamic.unsafe_encode
dynamic.decode              dynamic.unsafe_decode
dynamic.decode_into         dynamic.unsafe_decode_into
```

Regular dynamic decode requires the entire source buffer to be consumed. Dynamic arrays, objects, delta arrays, and RLE arrays support output reuse.

## Whole-Buffer Compression

`Serdes.compressed` wraps fixed codecs with whole-buffer Zstd compression through Roblox `EncodingService`:

```luau
local compressed = Serdes.compressed.encode(snapshot, value)
local decoded = Serdes.compressed.decode(snapshot, compressed)
```

```text
compressed.encode(codec, value, compression_level?)
compressed.unsafe_encode(codec, value, compression_level?)
compressed.decode(codec, source)
compressed.unsafe_decode(codec, source)
```

The default compression level is `1`; accepted levels are integers from `-7` through `22`. Encoding first creates the complete uncompressed fixed buffer, then compresses it once with `Enum.CompressionAlgorithm.Zstd`.

Regular decompression calls `EncodingService:GetDecompressedBufferSize` and requires it to equal `codec.size` before decompressing and running regular decode. Unsafe decompression skips the Serdes size and semantic checks. See the [Roblox EncodingService API](https://create.roblox.com/docs/reference/engine/classes/EncodingService).

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

* `array_unsafe_write`, `array_write`, fresh equivalents, `array_read`, and `array_unsafe_read` for specialized arrays
* `bits`, `unsafe_pack`, `pack`, `unpack`, and `unsafe_unpack` for `packed`
* `delta_safe = true` for value-like delta fields

Dynamic codecs use:

```luau
export type DynamicCodec<T> = {
	read measure: (value: T) -> number,
	read unsafe_write: (target: buffer, offset: number, value: T) -> number,
	read write: (target: buffer, offset: number, value: T) -> number,
	read read: (source: buffer, offset: number, output: T?) -> (T, number),
	read unsafe_read: (source: buffer, offset: number, output: T?) -> (T, number),

	read value_like: boolean?,
}
```

Returned offsets point to the first byte after the value. A dynamic codec may expose `value_like = true` if shallow equality is valid for RLE.

## Wire Compatibility and Limits

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
* Choose `cframe_12` for bandwidth, `cframe_28` for balance, and `cframe_48` for CPU-first encoding.
* Use `delta` when changes are sparse and a synchronized baseline already exists.
* Use the dynamic profile and compression for storage-oriented workloads, not by default on hot packet paths.
* Keep fixed string capacities and maximum dynamic counts realistic.

Generic composites still perform one cached indirect child call per field or element. Removing that final layer would require generated or straight-line schema code, which Serdes intentionally does not use.

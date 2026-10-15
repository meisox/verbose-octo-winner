# Migrating from 0327edf

This revision is a protocol/API update. Keep the old codec implementation available while migrating saved buffers, and version network packets so both peers select the same schema. There is no reliable way to infer the schema version from a buffer alone.

| Existing format | New format |
| --- | --- |
| 17–24 meaningful bits stored in four bytes | Three bytes for bits, ranges, enums, and packed records |
| Four-byte fixed dynamic prefix above 65,535 | Three bytes through 16,777,215; four beyond that |
| Delta mask width rounded to 1/2/4 bytes | Exactly `ceil(field_count/8)` bytes, including more than 32 fields |

Decode historical data with its historical schema, then re-encode using the new schema. These formats are not self-describing. Field order, enum order, bounds, and bit widths remain part of the protocol.

Prefer `struct({id = u32, ...})` and `packed_struct` for precise record inference. Their default field order is lexicographic; specify an order explicitly when matching an existing ordered object. `object({field(...)})` still supports runtime field lists and produces a string-keyed record type. A dictionary-annotated named schema now reports a type error instead of silently inferring `{}`.

Fixed codecs can be supplied directly to dynamic containers. Existing `dynamic.fixed(codec)` calls continue to work. Dynamic strings/arrays/RLE/delta arrays use fixed prefixes by default; opt into a canonical varint prefix with the last argument `"varint"` when useful. New tagged unions use `{tag = "variant", value = payload}`. Dynamic maps require lossless, ordered keys and nonnullable values.

Nullable dynamic arrays, RLE arrays, and ad hoc fixed batches require `table.pack(...).n` to preserve trailing nils. Their decoders return `n`. Schema-sized fixed arrays and tuples already know their cardinality and use ordinary numeric tables.

Custom dynamic codecs must implement validating `measure`, unchecked `unsafe_measure`, and a conservative `min_size`. Supply `max_size` where possible; compressed decoding requires an explicit maximum for an unbounded codec. Measurement must validate the full value because public encoding can use the unchecked writer afterward. Metadata and inputs must stay stable between measuring and writing.

Ordinary compression remains a Zstd frame. `compressed.adaptive` is a separate format with a raw/compressed marker and must be decoded with the matching API. Compression supports fixed and dynamic schemas, levels -7 through 22, and optional lower decompressed-size limits.

Checked quaternion encoders now reject matrices that are not proper rotations and normalize converted quaternions. Readers reject invalid norms, impossible smallest-three triples, and nonzero spare bits. Existing valid quaternion layouts remain readable; normalization may change newly encoded bytes slightly. Use `cframe_48` when preserving an arbitrary finite matrix is intentional. The new vector and CFrame factories are separate formats and do not replace the old presets automatically.

Checked offset APIs verify the entire region, including zero-byte values. Blob reuse requires an exactly sized buffer. Fixed sequence readers remove old trailing entries. Safe delta decoding validates and stages changes before updating a plain writable baseline; malformed deltas leave that baseline unchanged. Other composite readers and writers can update earlier children before a later validation error, so they do not offer transactional output reuse.

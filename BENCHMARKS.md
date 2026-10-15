# Measured performance

Measurements compare baseline `0327edf02a82b52bd1d1401b98d253e98dfe7ced` with this implementation. They are fixture results, not a guarantee for every schema, device, or engine build. Both gains and regressions are included.

## Roblox Studio

Measured on a Windows desktop in Studio Server, engine `0.742.0.7421053`. Both versions run in the same process with their native-compilation annotations. Each row is the median of seven trials after two warmups; before/after order alternates. Allocation is included in encode; decoding reuses the output. The runner yields between paired trials. Original Roblox import paths are mechanically corrected so the intended baseline can load; codec algorithms are unchanged.

Raw results: [studio-results.json](benchmarks/studio-results.json). Runner: [benchmarks/studio.luau](benchmarks/studio.luau), built with `node scripts/build-studio-benchmark.cjs`. Source snapshot: `064e6df8d18c1ff6c393a6eab6ea78ac5cb7e599aae210316ff5c53e1bfee433`.

**New/old is elapsed-time ratio: below 1 is faster.** Nanosecond values are averages per operation within each trial, not individual timer samples.

| Fixture | Operation | Bytes old/new | Old ns | New ns | New/old |
| --- | --- | ---: | ---: | ---: | ---: |
| packed24 | encode | 4/3 | 126.6 | 81.7 | 0.645 |
| packed24 | decode_reuse | 4/3 | 125.3 | 83.9 | 0.670 |
| snapshot | encode | 18/18 | 166.7 | 121.9 | 0.732 |
| snapshot | decode_reuse | 18/18 | 167.0 | 115.4 | 0.691 |
| fixed_u32_256 | encode | 1024/1024 | 4039.0 | 3998.9 | 0.990 |
| fixed_u32_256 | decode_reuse | 1024/1024 | 681.2 | 740.6 | 1.087 |
| dynamic_u32_256 | encode | 1026/1026 | 14096.0 | 5307.9 | 0.377 |
| dynamic_u32_256 | decode_reuse | 1026/1026 | 7629.5 | 747.0 | 0.098 |
| dynamic_record | encode | 413/413 | 4493.7 | 1466.9 | 0.326 |
| dynamic_record | decode_reuse | 413/413 | 2796.1 | 463.7 | 0.166 |
| rle_256 | encode | 5/5 | 1569.0 | 1605.2 | 1.023 |
| rle_256 | decode_reuse | 5/5 | 703.4 | 712.4 | 1.013 |
| varu32 | encode | 2/2 | 68.2 | 59.5 | 0.873 |
| varu32 | decode_reuse | 2/2 | 50.3 | 53.0 | 1.054 |
| string_12 | encode | 13/13 | 92.0 | 95.8 | 1.040 |
| string_12 | decode_reuse | 13/13 | 73.8 | 68.2 | 0.924 |
| cframe_12 | encode | 12/12 | 133.7 | 175.9 | 1.315 |
| cframe_12 | decode_reuse | 12/12 | 127.3 | 107.4 | 0.844 |
| cframe_28 | encode | 28/28 | 145.6 | 174.9 | 1.201 |
| cframe_28 | decode_reuse | 28/28 | 122.5 | 142.8 | 1.166 |
| cframe_48 | encode | 48/48 | 154.5 | 159.4 | 1.032 |
| cframe_48 | decode_reuse | 48/48 | 123.1 | 132.0 | 1.072 |

The largest measured gains come from dynamic fixed-element arrays using bulk validation and bulk I/O instead of one adapter call per element. Dynamic records benefit when they contain these arrays. Packed 24-bit records save one byte and use a narrower path. The snapshot fixture remains 18 bytes; its particular combination of range and packed integer codecs also improved.

Quaternion encoding has an explicit cost: `cframe_12` encoding took about 32% longer, and `cframe_28` about 20% longer in this run, after adding proper-rotation validation and unit normalization. Fixed-array reuse decoding took about 9% longer; it now removes stale trailing entries. Small scalar/RLE results and the unchanged `cframe_48` implementation show ordinary run-to-run variation. Repeated measurements during development varied, especially for sub-microsecond cases. These results do not establish a universal speedup.

The new `cframe_16` fixture measured 273.9 ns encode, 213.0 ns unchecked encode, and 216.9 ns decode. It saves about 43% against 28 bytes while preserving float32 position and bounding rotation error to 0.275 degrees. Its bit-oriented rotation path is slower than the 28-byte preset in this fixture.

## Luau CLI

Raw native and interpreted results, commands, timestamp, and source digest are in [cli-results.json](benchmarks/cli-results.json). Reproduce with `node scripts/benchmark.cjs` after fetching the baseline commit. CLI and Studio runners hash their snapshots differently. CLI timings describe the standalone VM and do not substitute for engine measurements.

Selected elapsed-time ratios from the final CLI run:

| Fixture | Mode | Operation | New/old |
| --- | --- | --- | ---: |
| compare/packed24 | native | write | 0.503 |
| compare/packed24 | native | read_reuse | 0.499 |
| compare/array_u32_256 | native | write | 1.003 |
| compare/array_u32_256 | native | read_reuse | 0.992 |
| dynamic/array_u32_256 | native | encode | 0.196 |
| dynamic/array_u32_256 | native | decode_reuse | 0.096 |
| dynamic/object | native | encode | 0.218 |
| dynamic/object | native | decode_reuse | 0.191 |
| dynamic/rle_256 | native | encode | 1.009 |
| dynamic/rle_256 | native | decode_reuse | 0.693 |
| compare/packed24 | interpreted | write | 1.084 |
| compare/packed24 | interpreted | read_reuse | 0.951 |
| compare/array_u32_256 | interpreted | write | 0.978 |
| compare/array_u32_256 | interpreted | read_reuse | 1.078 |
| dynamic/array_u32_256 | interpreted | encode | 0.555 |
| dynamic/array_u32_256 | interpreted | decode_reuse | 0.275 |
| dynamic/object | interpreted | encode | 0.574 |
| dynamic/object | interpreted | decode_reuse | 0.329 |
| dynamic/rle_256 | interpreted | encode | 1.077 |
| dynamic/rle_256 | interpreted | decode_reuse | 1.053 |

The interpreted packed24 writer trades some CPU for the smaller wire layout. RLE validates input and validates runs before expansion; these checks can cost more even when encoded bytes are unchanged. Keep the checked path at trust boundaries, and use unchecked operations only when the value or buffer is already valid.

## Other size improvements

- 100 packed booleans occupy 13 bytes instead of a 100-byte ordinary boolean array. This is an explicit schema choice.
- A 17-field delta uses a three-byte change mask instead of four; wide deltas support more than 32 fields.
- Configurable vectors use exactly the requested per-axis bits plus byte padding, preserve zero, and expose precision bounds.
- Optional varint lengths, compact dynamic optionals, and deterministic tagged unions/maps let schemas fit their actual domains.
- Adaptive compression stores raw bytes when Zstd would expand them, with one framing byte.

Benchmark data is recorded for review. Timings should be rerun for application schemas before selecting a profile; do not compare these absolute numbers with unrelated machines.

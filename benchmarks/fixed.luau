-- Pure Luau; imports the actual unmodified source, without a custom environment.
-- Run interpreted and native: luau -O2 benchmarks/fixed.luau / luau -O2 --codegen benchmarks/fixed.luau
local u8 = require("../src/Primitive/u8")
local u16 = require("../src/Primitive/u16")
local u32 = require("../src/Primitive/u32")
local array = require("../src/Composite/array")
local packed = require("../src/Composite/packed")
local bits = require("../src/Primitive/bits")
local quantized = require("../src/Composite/quantized")
local function bench(name,codec,value,iterations)
    local packet = buffer.create(codec.size)
    local samples = {}
    for trial=1,7 do
        local start = os.clock()
        for _=1,iterations do codec.write(packet,0,value) end
        samples[trial] = (os.clock()-start)/iterations*1e9
    end
    table.sort(samples)
    print(string.format("%s,%d,write,%.1f",name,codec.size,samples[4]))
    local output = codec.read(packet,0)
    table.clear(samples)
    for trial=1,7 do
        local start = os.clock()
        for _=1,iterations do output = codec.read(packet,0,output) end
        samples[trial] = (os.clock()-start)/iterations*1e9
    end
    table.sort(samples)
    print(string.format("%s,%d,read_reuse,%.1f",name,codec.size,samples[4]))
end
print("case,bytes,operation,median_ns")
bench("u8",u8,127,200000)
bench("bits20",bits(20),500000,200000)
bench("quantized16",quantized(-10,10,16),1.25,200000)
bench("packed24",packed({{name="a",codec=bits(12)},{name="b",codec=bits(12)}}),{a=1023,b=2049},100000)
local values=table.create(256,127)
bench("array_u8_256",array(u8,256),values,10000)
bench("array_u16_256",array(u16,256),values,10000)
bench("array_u32_256",array(u32,256),values,10000)

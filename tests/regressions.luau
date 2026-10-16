-- Run: node scripts/prepare-tests.cjs && lune run tests/regressions.luau
local S = require("./.generated/src/index")
local passed, failed = 0, 0
local function test(name, callback)
    local ok, problem = pcall(callback)
    if ok then
        passed += 1
    else
        failed += 1
        print(`FAIL {name}: {problem}`)
    end
end
local function throws(callback)
    assert(not pcall(callback), "expected rejection")
end
local function equal(a, b)
    assert(a == b, `expected {b}, got {a}`)
end
local function roundtrip(codec, value)
    return S.decode(codec, S.encode(codec, value))
end

test("primitive extrema", function()
    for _, pair in {{S.u8,255},{S.i8,-128},{S.u16,65535},{S.i16,-32768},{S.u32,4294967295},{S.i32,-2147483648},{S.f32,1.5},{S.f64,1e200},{S.bool,true}} do
        equal(roundtrip(pair[1],pair[2]),pair[2])
    end
    throws(function() S.encode(S.u32, -1) end)
    throws(function() S.decode(S.bool,buffer.fromstring("\2")) end)
end)

test("fixed adapter clears reused bytes", function()
    for _, value in {"", "x", "hello"} do
        local fixed = S.string(5)
        local adapted = S.dynamic.fixed(fixed)
        local target = buffer.fromstring(string.rep("\255", fixed.size))
        equal(adapted.write(target,0,value),fixed.size)
        equal(buffer.tostring(target),buffer.tostring(S.encode(fixed,value)))
    end
    local fixed = S.optional(S.u32)
    local target = buffer.fromstring(string.rep("\255",fixed.size))
    S.dynamic.fixed(fixed).unsafe_write(target,0,nil)
    equal(buffer.tostring(target),buffer.tostring(S.encode(fixed,nil)))
end)

test("safe offsets validate full region", function()
    local codec = S.optional(S.u32)
    throws(function() S.from(codec,buffer.create(1),0) end)
    throws(function() S.from(S.string(10),buffer.create(1),0) end)
    for _, offset in {-1,0.5,1,math.huge,0/0} do
        throws(function() S.from(S.range(7,7),buffer.create(0),offset) end)
        throws(function() S.into(S.range(7,7),buffer.create(0),offset,7) end)
    end
    equal(S.from(S.range(7,7),buffer.create(0),0),7)
end)

test("fixed arrays and tuples trim output", function()
    for _, codec in {S.array(S.u8,2), S.array(S.range(0,100),2), S.tuple({S.u8,S.u8})} do
        local packet = S.encode(codec,{1,2})
        for _, decode in {S.decode_into,S.unsafe_decode_into} do
            local output = {9,9,9,9}
            equal(decode(codec,packet,output),output)
            equal(#output,2)
            equal(output[1],1)
            equal(output[2],2)
        end
    end
end)

test("trailing optional tuple and array values", function()
    for _, codec in {S.array(S.optional(S.u8),2),S.tuple({S.u8,S.optional(S.u8)})} do
        local result = roundtrip(codec,{1})
        equal(result[1],1)
        equal(result[2],nil)
        codec.validate(result)
        throws(function() S.encode(codec,{1,nil,3}) end)
    end
end)

test("blob reuses only exact sized outputs", function()
    local codec = S.blob(2)
    local packet = buffer.fromstring("hi")
    for _, size in {0,1,2,3,9} do
        local output = buffer.create(size)
        local decoded = S.decode_into(codec,packet,output)
        equal(buffer.tostring(decoded),"hi")
        if size == 2 then equal(decoded,output) end
    end
end)

test("failed delta decode leaves baseline unchanged", function()
    local codec = S.delta(S.object({S.field("a",S.u8),S.field("b",S.bool)}))
    local good = codec.encode({a=1,b=false},{a=9,b=true})
    local semantic = buffer.fromstring(buffer.tostring(good))
    buffer.writeu8(semantic,buffer.len(semantic)-1,2)
    for _, packet in {buffer.fromstring(buffer.tostring(good).."x"),buffer.fromstring(string.sub(buffer.tostring(good),1,-2)),semantic} do
        local baseline = {a=1,b=false}
        throws(function() codec.decode_into(packet,baseline) end)
        equal(baseline.a,1)
        equal(baseline.b,false)
    end
end)

test("quantization supports finite extreme ranges", function()
    for _, interval in {{-1e308,1e308},{0,1e-310},{1e300,1.0001e300},{-10,10},{0,1}} do
        local lo, hi = interval[1], interval[2]
        local codec = S.quantized(lo,hi,16)
        local previous = lo
        for i=0,100 do
            local value = (1-i/100)*lo + (i/100)*hi
            local decoded = roundtrip(codec,value)
            assert(math.isfinite(decoded) and decoded >= lo and decoded <= hi, "nonfinite or out of interval")
            assert(decoded >= previous,"not monotonic")
            previous = decoded
        end
        equal(roundtrip(codec,lo),lo)
        equal(roundtrip(codec,hi),hi)
    end
end)

test("small integers occupy minimum whole bytes",function()
    for width=1,32 do
        local codec = S.bits(width)
        equal(codec.size,math.ceil(width/8))
        equal(roundtrip(codec,2^width-1),2^width-1)
    end
    equal(S.range(0,65536).size,3)
end)

test("quantization supports every width",function()
    for width=1,32 do
        local codec = S.quantized(-10,10,width)
        equal(codec.size,math.ceil(width/8))
        equal(roundtrip(codec,-10),-10)
        equal(roundtrip(codec,10),10)
        if width%8 ~= 0 then
            throws(function() S.decode(codec,buffer.fromstring(string.rep("\255",codec.size))) end)
        end
    end
end)

print(`Regression tests: {passed} passed, {failed} failed`)
assert(failed == 0, `Failed {failed} regression tests`)

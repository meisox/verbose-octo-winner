local S = require("./.generated/src/index")
local D = S.dynamic
local cases = 0
local function equal(a,b) assert(a==b,`expected {b}, got {a}`) end
local function fails(callback) assert(not pcall(callback),"expected rejection") end
local function varint(n)
	local bytes={}
	repeat
		local low=n%128
		n=math.floor(n/128)
		bytes[#bytes+1]=string.char(low+(if n>0 then 128 else 0))
	until n==0
	return table.concat(bytes)
end
local function roundtrip(codec,value,expected)
	local encoded=D.encode(codec,value)
	equal(buffer.len(encoded),codec.measure(value))
	equal(codec.unsafe_measure(value),buffer.len(encoded))
	if expected then equal(buffer.tostring(encoded),expected) end
	equal(buffer.tostring(D.unsafe_encode(codec,value)),buffer.tostring(encoded))
	local target=buffer.fromstring(string.rep("\255",buffer.len(encoded)+7))
	equal(D.into(codec,target,3,value),buffer.len(encoded)+3)
	equal(buffer.readstring(target,3,buffer.len(encoded)),buffer.tostring(encoded))
	equal(buffer.readstring(target,0,3),"\255\255\255")
	equal(buffer.readstring(target,3+buffer.len(encoded),4),"\255\255\255\255")
	local decoded,position=D.from(codec,target,3)
	equal(position,3+buffer.len(encoded))
	if not codec.nullable or decoded~=nil then
		equal(buffer.tostring(D.encode(codec,decoded)),buffer.tostring(encoded))
	end
	cases+=1
	return D.decode(codec,encoded)
end

local boundaries={0,1,127,128,255,16383,16384,2097151,2097152,268435455,268435456,4294967295}
for _,n in boundaries do equal(roundtrip(D.varu32,n,varint(n)),n) end
math.randomseed(735)
for _=1,1000 do
	local n=math.random(0,65535)*65536+math.random(0,65535)
	equal(roundtrip(D.varu32,n,varint(n)),n)
end
for _,n in {-2147483648,-1000,-64,-1,0,1,63,64,2147483647} do
	equal(roundtrip(D.vari32,n,varint(if n<0 then -2*n-1 else 2*n)),n)
end
for _,codec in {D.varu32,D.vari32} do
	for _,value in {0/0,math.huge,-math.huge,1.5,"x",{}} do fails(function()codec.measure(value)end) end
end
for _,encoded in {"\128\0","\255\255\255\255\16","\128","\128\128\128\128\128"} do
	fails(function()D.decode(D.varu32,buffer.fromstring(encoded))end)
end

for _,maximum in {0,255,256,65535,65536,16777216} do
	for _,mode in {"fixed","varint"} do
		local string_codec=D.string(maximum,mode)
		for _,value in {"",string.rep("x",math.min(130,maximum))} do equal(roundtrip(string_codec,value),value) end
		fails(function()string_codec.measure(42)end)
		if maximum<1000 then fails(function()string_codec.measure(string.rep("x",maximum+1))end) end
	end
end
equal(buffer.len(D.encode(D.string(100000,"varint"),"")),1)
equal(buffer.len(D.encode(D.string(100000),"")),3)

for _,child in {S.u8,S.u16,S.u32,S.range(0,100),D.varu32} do
	for _,mode in {"fixed","varint"} do
		local codec=D.array(child,1000,mode)
		local decoded=roundtrip(codec,{1,2,3,4})
		equal(#decoded,4)
		for i=1,4 do equal(decoded[i],i) end
		local output={9,9,9,9,9}
		equal(D.decode_into(codec,D.encode(codec,{5,6}),output),output)
		equal(#output,2)
		equal(output[1],5)
		fails(function()D.decode(codec,buffer.fromstring(string.sub(buffer.tostring(D.encode(codec,{5,6})),1,-2)))end)
	end
end

local optional=D.optional(S.u32)
equal(roundtrip(optional,nil,"\0"),nil)
equal(roundtrip(optional,4294967295,"\1\255\255\255\255"),4294967295)
fails(function()D.decode(optional,buffer.fromstring("\2"))end)
local nullable=D.array(optional,10)
local sparse=roundtrip(nullable,table.pack(1,nil,3,nil))
equal(sparse.n,4);equal(sparse[1],1);equal(sparse[2],nil);equal(sparse[3],3);equal(sparse[4],nil)
fails(function()nullable.measure({1,nil,3})end)
local reuse=table.pack(9,9,9,9,9)
D.decode_into(nullable,D.encode(nullable,table.pack(nil,2)),reuse)
equal(reuse.n,2);equal(reuse[1],nil);equal(reuse[2],2);equal(reuse[5],nil)

local object=D.struct({id=S.u16,name=D.string(10),target=D.optional(S.u8)},{"id","name","target"})
local decoded=roundtrip(object,{id=513,name="ab",target=nil},"\1\2\2ab\0")
equal(decoded.id,513);equal(decoded.name,"ab");equal(decoded.target,nil)
local reused={id=0,name="old",target=9}
equal(D.decode_into(object,D.encode(object,decoded),reused),reused)
equal(reused.target,nil)
local tuple=D.tuple({S.u16,D.string(10),D.optional(S.u8)})
decoded=roundtrip(tuple,{513,"ab"},"\1\2\2ab\0")
equal(decoded[1],513);equal(decoded[2],"ab");equal(decoded[3],nil)
roundtrip(D.struct({}),{},"")
roundtrip(D.tuple({}),{},"")

for _,codec in {D.delta_array(1000),D.rle(S.u32,1000),D.array(S.u32,1000)} do
	for _,values in {{},{1},{1,1,2,2,2,100},{4294967295,4294967295}} do
		local output=roundtrip(codec,values)
		equal(#output,#values)
		for i,v in values do equal(output[i],v) end
	end
	fails(function()codec.measure("x")end)
end
fails(function()D.delta_array(10).measure({3,2})end)
fails(function()D.delta_array(1).measure({1,2})end)
fails(function()D.rle(S.u8,1).measure({1,2})end)
local nil_runs=D.rle(D.optional(S.u8),10)
decoded=roundtrip(nil_runs,table.pack(nil,nil,7,nil))
equal(decoded.n,4);equal(decoded[1],nil);equal(decoded[3],7)

-- Large declared counts in short malformed packets must reject before any
-- large allocation or expansion. A sentinel output must remain untouched.
local huge=1000000000
for _,codec in {D.array(S.u8,huge),D.delta_array(huge)} do
	local payload=if codec.min_size==4 then "\0\202\154\59" else varint(huge)
	fails(function()D.decode(codec,buffer.fromstring(payload))end)
end
local compressed=D.rle(S.u8,huge)
local sentinel={42}
fails(function()D.decode_into(compressed,buffer.fromstring(varint(huge).."\1"..varint(huge-1)),sentinel)end)
equal(#sentinel,1);equal(sentinel[1],42)
fails(function()D.decode(compressed,buffer.fromstring("\1\0\0"))end)
fails(function()D.unsafe_decode(compressed,buffer.fromstring("\1\0\0"))end)

local blob=D.blob(1000,"varint")
local data=buffer.fromstring("binary\0data")
equal(buffer.tostring(roundtrip(blob,data)),buffer.tostring(data))
local output=buffer.create(buffer.len(data))
equal(D.decode_into(blob,D.encode(blob,data),output),output)
equal(buffer.len(D.decode_into(blob,D.encode(blob,data),buffer.create(1))),buffer.len(data))
fails(function()D.decode(blob,buffer.fromstring(varint(1000).."x"))end)

local guarded=table.clone(D.varu32)
local wrote=false
guarded.measure=function()return 1073741825 end
guarded.unsafe_write=function()wrote=true;error("must not write")end
fails(function()D.encode(guarded,1)end)
equal(wrote,false)
local dirty=buffer.fromstring("unchanged")
fails(function()D.into(object,dirty,0,{id=-1,name="ab"})end)
equal(buffer.tostring(dirty),"unchanged")

local variant=D.union({message=D.string(20),count=S.u32},{"message","count"})
decoded=roundtrip(variant,{tag="message",value="hi"},"\0\2hi")
equal(decoded.tag,"message");equal(decoded.value,"hi")
decoded=roundtrip(variant,{tag="count",value=7},"\1\7\0\0\0")
equal(decoded.value,7)
local single=D.union({ready=S.range(1,1)})
decoded=roundtrip(single,{tag="ready",value=1},"")
equal(decoded.tag,"ready");equal(decoded.value,1)
fails(function()variant.measure({tag="unknown",value=0})end)
fails(function()D.decode(variant,buffer.fromstring("\2"))end)
local different=D.union({bytes=D.blob(10),record=D.struct({id=S.u8})})
local reused_variant=D.decode(different,D.encode(different,{tag="bytes",value=buffer.fromstring("abc")}))
D.decode_into(different,D.encode(different,{tag="record",value={id=9}}),reused_variant)
equal(reused_variant.tag,"record");equal(reused_variant.value.id,9)

local dictionary=D.map(D.string(10),S.u16,10,"varint")
decoded=roundtrip(dictionary,{b=2,a=1},"\2\1a\1\0\1b\2\0")
equal(decoded.a,1);equal(decoded.b,2)
equal(buffer.tostring(D.encode(dictionary,{a=1,b=2})),buffer.tostring(D.encode(dictionary,{b=2,a=1})))
local reused_map={a=7,stale=8}
equal(D.decode_into(dictionary,D.encode(dictionary,{b=2}),reused_map),reused_map)
equal(reused_map.a,nil);equal(reused_map.stale,nil);equal(reused_map.b,2)
fails(function()D.decode(dictionary,buffer.fromstring("\2\1a\1\0\1a\2\0"))end)
fails(function()D.decode(dictionary,buffer.fromstring("\2\1b\1\0\1a\2\0"))end)
fails(function()D.map(S.quantized(0,1,8),S.u8,10)end)
fails(function()D.map(S.u8,D.optional(S.u8),10)end)
local numeric=D.map(S.u8,D.string(10),10)
decoded=roundtrip(numeric,{[3]="c",[1]="a"},"\2\1\1a\3\1c")
equal(decoded[1],"a");equal(decoded[3],"c")
local booleans=D.map(S.bool,S.u8,2)
roundtrip(booleans,{[false]=1,[true]=2},"\2\0\1\1\2")
local enum_key_1,enum_key_2={},{}
local enumeration=D.map(S.enum({enum_key_1,enum_key_2}),S.u8,2)
decoded=roundtrip(enumeration,{[enum_key_2]=2,[enum_key_1]=1},"\2\0\1\1\2")
equal(decoded[enum_key_1],1);equal(decoded[enum_key_2],2)
local quantized=S.quantized(0,1,8)
local quantized_runs=D.rle(quantized,10)
local packed_runs=D.encode(quantized_runs,{0.5,0.5001,0.5002})
equal(buffer.len(packed_runs),3) -- count, one quantized value, run length
equal(buffer.tostring(D.encode(quantized_runs,D.decode(quantized_runs,packed_runs))),buffer.tostring(packed_runs))
fails(function()quantized_runs.measure({1,1.0001})end) -- rounds to the same code, but is outside the domain
fails(function()quantized_runs.write(buffer.create(20),0,{1,1.0001})end)
for _,entry in {
	{S.u8,0,256},{S.u16,0,-1},{S.u32,0,4294967296},
	{S.i8,0,-129},{S.i16,0,32768},{S.i32,0,-2147483649},
	{S.f32,0,1e39},{S.f64,0,math.huge},{S.bool,false,0},
} do
	local codec=D.array(entry[1],10)
	fails(function()codec.measure({entry[2],entry[3]})end)
	fails(function()D.encode(codec,{entry[2],entry[3]})end)
	for _,count in {0,1,2,3,5,7,8,9} do
		local decoded=roundtrip(codec,table.create(count,entry[2]))
		equal(#decoded,count)
	end
end
print(`Dynamic tests: {cases} roundtrips plus malformed input, allocation, and reuse checks passed`)

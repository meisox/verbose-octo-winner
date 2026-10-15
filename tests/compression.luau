local S=require("./.generated/src/index")
if game==nil then print("Compression tests require Roblox Studio; skipped in Lune") return end
local C,D=S.compressed,S.dynamic
local function fails(callback)assert(not pcall(callback),"expected rejection")end
local function equal(a,b)assert(a==b,`expected {b}, got {a}`)end
local fixed=S.struct({a=S.u32,b=S.bool})
local value={a=123,b=true}
for _,level in {-7,1,22} do
	local encoded=C.encode(fixed,value,level)
	local decoded=C.decode(fixed,encoded)
	equal(decoded.a,123);equal(decoded.b,true)
	local reused={a=0,b=false}
	equal(C.decode_into(fixed,encoded,reused),reused);equal(reused.a,123)
	equal(C.unsafe_decode(fixed,C.unsafe_encode(fixed,value,level)).a,123)
	fails(function()C.decode(S.u8,encoded)end)
	fails(function()C.decode(fixed,encoded,4)end)
end
for _,level in {-8,23,1.5,0/0} do fails(function()C.encode(fixed,value,level)end)end

local schema=D.struct({name=D.string(1000),items=D.array(S.u32,1000)})
local saved={name=string.rep("name",100),items=table.create(256,7)}
for _,profile in {C,C.adaptive} do
	local encoded=profile.encode(schema,saved)
	local decoded=profile.decode(schema,encoded)
	equal(decoded.name,saved.name);equal(#decoded.items,256);equal(decoded.items[128],7)
	local reused={name="old",items={1,2,3}}
	local items=reused.items
	equal(profile.decode_into(schema,encoded,reused),reused)
	equal(reused.items,items);equal(#items,256)
	fails(function()profile.decode(schema,encoded,1)end)
end
local no_bound=table.clone(D.string(100))
no_bound.max_size=nil
local encoded=C.encode(no_bound,"test")
fails(function()C.decode(no_bound,encoded)end)
equal(C.decode(no_bound,encoded,100),"test")

local zeros=S.blob(1000)
local encoded=C.adaptive.encode(zeros,buffer.create(1000))
equal(buffer.readu8(encoded,0),1)
assert(buffer.len(encoded)<1000)
equal(buffer.len(C.adaptive.decode(zeros,encoded)),1000)
math.randomseed(726)
local noise=buffer.create(256)
for i=0,255 do buffer.writeu8(noise,i,math.random(0,255))end
encoded=C.adaptive.encode(S.blob(256),noise)
equal(buffer.readu8(encoded,0),0)
equal(buffer.len(encoded),257)
equal(buffer.tostring(C.adaptive.decode(S.blob(256),encoded)),buffer.tostring(noise))
fails(function()C.adaptive.decode(S.blob(1),encoded)end)
fails(function()C.adaptive.decode(S.u8,buffer.fromstring("\2"))end)
fails(function()C.adaptive.decode(S.u8,buffer.create(0))end)
fails(function()C.adaptive.decode(D.string(20),buffer.fromstring("\0\1ax"))end)
fails(function()C.decode(fixed,buffer.fromstring("invalid"))end)
encoded=C.encode(schema,saved)
fails(function()C.decode(schema,buffer.fromstring(string.sub(buffer.tostring(encoded),1,-2)))end)
print("Compression tests: fixed/dynamic Zstd, size limits, output reuse, malformed frames and adaptive raw fallback passed")

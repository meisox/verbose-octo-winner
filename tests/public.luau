local S = require("./.generated/src/index")
local function throws(callback) assert(not pcall(callback),"expected rejection") end
local function same(a,b) assert(buffer.tostring(a)==buffer.tostring(b),"wire mismatch") end
local cases={
	{S.bool,{false,true}}, {S.i8,{-128,-1,0,127}}, {S.u8,{0,1,255}},
	{S.i16,{-32768,-1,0,32767}}, {S.u16,{0,256,65535}},
	{S.i32,{-2147483648,-1,0,2147483647}}, {S.u32,{0,65536,4294967295}},
	{S.f32,{-3e38,-1.5,0,3e38}}, {S.f64,{-1e300,-0.5,0,1e300}},
	{S.string(6),{"","abc","\0a\255"}}, {S.range(7,7),{7}},
	{S.enum({"one","two","three"}),{"one","two","three"}},
}
local routes=0
for _,case in cases do
	local codec,values=case[1],case[2]
	for _,value in values do
		local bytes=S.encode(codec,value)
		same(bytes,S.unsafe_encode(codec,value))
		local canonical=S.encode(codec,S.decode(codec,bytes))
		same(bytes,canonical)
		same(bytes,S.encode(codec,S.unsafe_decode(codec,bytes)))
		for _,write in {S.into,S.unsafe_into} do
			local target=buffer.fromstring(string.rep("\255",codec.size+4))
			assert(write(codec,target,2,value)==codec.size+2)
			for _,read in {S.from,S.unsafe_from} do
				local decoded,next_offset=read(codec,target,2)
				assert(next_offset==codec.size+2);same(bytes,S.encode(codec,decoded))
			end
		end
		for length=0,codec.size-1 do throws(function() S.decode(codec,buffer.create(length)) end) end
		throws(function() S.decode(codec,buffer.create(codec.size+1)) end)
		routes+=1
	end
	if codec.size>0 then
		local bytes=S.encode_many(codec,values);same(bytes,S.unsafe_encode_many(codec,values))
		for _,decode in {S.decode_many,S.unsafe_decode_many} do same(bytes,S.encode_many(codec,decode(codec,bytes))) end
		local reuse=table.clone(values);reuse[#values+1]=values[1]
		for _,decode in {S.decode_many_into,S.unsafe_decode_many_into} do
			assert(decode(codec,bytes,reuse)==reuse and #reuse==#values);same(bytes,S.encode_many(codec,reuse))
		end
	end
end
local optional=S.optional(S.u8)
local nullable=table.pack(1,nil,3,nil)
local bytes=S.encode_many(optional,nullable)
same(bytes,S.unsafe_encode_many(optional,nullable))
for _,decode in {S.decode_many,S.unsafe_decode_many} do
	local result=decode(optional,bytes)
	assert(result.n==4 and result[1]==1 and result[2]==nil and result[3]==3 and result[4]==nil)
end
throws(function() S.encode_many(optional,{1}) end)
for count=1,65 do
	local names,value={},{}
	for i=1,count do names[i]="flag"..i;value[names[i]]=i%3==0 end
	local codec=S.flags(names)
	local encoded=S.encode(codec,value)
	assert(buffer.len(encoded)==math.ceil(count/8))
	for i=1,count do
		local mask=2^((i-1)%8)
		assert((bit32.band(buffer.readu8(encoded,math.floor((i-1)/8)),mask)~=0)==value[names[i]])
	end
	assert(S.decode_into(codec,encoded,value)==value)
	if count%8~=0 then
		buffer.writeu8(encoded,codec.size-1,255)
		throws(function() S.decode(codec,encoded) end)
	end
end
for _,list in {{[2]=S.u8},{[1]=S.u8,[3]=S.u8},{[1]=S.u8,extra=S.u8}} do
	throws(function() S.tuple(list) end);throws(function() S.dynamic.tuple(list) end)
end
throws(function() S.enum({[2]="bad"}) end)
throws(function() S.flags({[2]="bad"}) end)
throws(function() S.object({[2]=S.field("x",S.u8)}) end)
throws(function() S.packed({[2]=S.field("x",S.u8)}) end)
throws(function() S.struct({x=S.u8},{[1]="x",[3]="x"}) end)
print(`Public API tests: {routes} scalar cases across offset/batch/unsafe routes, nullable batches, 65 flag layouts, malformed schemas passed`)

local S = require("./.generated/src/index")
local cases = 0
math.randomseed(0x534552)

-- Independent, intentionally slow bit-by-bit wire oracle. Does not use the
-- production packer, bit32.extract, or buffer.readbits/writebits.
local function reference(widths, values)
	local total = 0
	for _, width in widths do total += width end
	local bytes = table.create(math.ceil(total/8),0)
	local position = 0
	for index, width in widths do
		local value = values[index]
		for _ = 1, width do
			local byte = math.floor(position/8)+1
			bytes[byte] += (value%2)*2^(position%8)
			value = math.floor(value/2)
			position += 1
		end
	end
	local strings = {}
	for index, byte in bytes do strings[index] = string.char(byte) end
	return table.concat(strings)
end

local function verify(codec,value,expected,check)
	local fresh = S.encode(codec,value)
	assert(buffer.tostring(fresh)==expected,"wire mismatch")
	for _, write in {S.into,S.unsafe_into} do
		local target=buffer.fromstring(string.rep("\255",codec.size+8))
		assert(write(codec,target,3,value)==codec.size+3)
		assert(buffer.readstring(target,3,codec.size)==expected,"reused wire mismatch")
		assert(buffer.readstring(target,0,3)==string.rep("\255",3),"prefix modified")
		assert(buffer.readstring(target,3+codec.size,5)==string.rep("\255",5),"suffix modified")
		check(S.from(codec,target,3))
		check(S.unsafe_from(codec,target,3))
	end
	cases += 1
end

for width=1,32 do
	for _, count in {0,1,2,3,7,8,9,31,32,33,100} do
		local values,widths={},{}
		for i=1,count do
			values[i]=(math.random(0,65535)*65536+math.random(0,65535))%2^width
			widths[i]=width
		end
		local codec=S.packed_array(S.bits(width),count)
		verify(codec,values,reference(widths,values),function(decoded)
			assert(#decoded==count)
			for i=1,count do assert(decoded[i]==values[i]) end
		end)
		if width*count%8~=0 then
			local target=S.encode(codec,values)
			buffer.writeu8(target,codec.size-1,bit32.bor(buffer.readu8(target,codec.size-1),128))
			assert(not pcall(S.decode,codec,target),"accepted nonzero padding")
		end
	end
end

for _=1,500 do
	local fields,widths,values,record={},{},{},{}
	for i=1,math.random(1,40) do
		local width=math.random(0,32)
		local encoded=(math.random(0,65535)*65536+math.random(0,65535))%2^width
		local codec=if width==0 then S.range(42,42) else S.bits(width)
		fields[i]=S.field(tostring(i),codec)
		widths[i],values[i]=width,encoded
		record[tostring(i)]=if width==0 then 42 else encoded
	end
	local codec=S.packed(fields)
	verify(codec,record,reference(widths,values),function(decoded)
		for name,value in record do assert(decoded[name]==value,"field mismatch") end
	end)
end

verify(S.packed_array(S.bool,100),table.create(100,true),string.rep("\255",12).."\15",function(value)
	assert(#value==100)
	for i=1,100 do assert(value[i]==true) end
end)
verify(S.packed_array(S.range(42,42),5),table.create(5,42),"",function(value)
	assert(#value==5)
	for i=1,5 do assert(value[i]==42) end
end)
local enum=S.enum({"a","b","c"})
assert(not pcall(S.decode,S.packed_array(enum,1),buffer.fromstring("\3")))
assert(not pcall(S.packed_array,S.f32,3),"accepted nonpackable codec")
print(`Packing tests: {cases} cases passed against independent wire oracle`)

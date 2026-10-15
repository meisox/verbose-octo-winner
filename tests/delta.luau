local S = require("./.generated/src/index")
local cases=0
for _,count in {1,7,8,9,16,17,24,25,31,32,33,63,64,65,127} do
	local fields,baseline,current={},{},{}
	for i=1,count do
		fields[i]=S.field(tostring(i),S.u8)
		baseline[tostring(i)]=0
		current[tostring(i)]=0
	end
	local codec=S.delta(S.object(fields))
	local header=math.ceil(count/8)
	assert(buffer.len(codec.encode(baseline,current))==header)
	for changed=1,count do
		current[tostring(changed)]=changed%256
		for _,encode in {codec.encode,codec.unsafe_encode} do
			local packet=encode(baseline,current)
			assert(buffer.len(packet)==header+changed)
			for byte=0,header-1 do
				local set=math.clamp(changed-byte*8,0,8)
				assert(buffer.readu8(packet,byte)==2^set-1,"mask mismatch")
			end
			for _,decode in {codec.decode_into,codec.unsafe_decode_into} do
				local output=table.clone(baseline)
				assert(decode(packet,output)==output)
				for key,value in current do assert(output[key]==value) end
			end
		end
		cases+=1
	end
	if count%8~=0 then
		local packet=buffer.create(header)
		buffer.writeu8(packet,header-1,128)
		assert(not pcall(codec.decode_into,packet,baseline),"accepted invalid mask")
	end
	local packet=codec.encode(baseline,current)
	local invalid=buffer.fromstring(buffer.tostring(packet).."x")
	assert(not pcall(codec.decode_into,invalid,baseline))
	for _,value in baseline do assert(value==0,"failed decode changed baseline") end
	current["1"]=-1
	assert(not pcall(codec.encode,current,current),"did not validate unchanged value")
end

local fields={}
for i=1,40 do fields[i]=S.field(tostring(i),S.bool) end
local wide=S.delta(S.object(fields))
local old,new={},{}
for i=1,40 do old[tostring(i)]=false;new[tostring(i)]=true end
local packet=wide.encode(old,new)
buffer.writeu8(packet,buffer.len(packet)-1,2)
assert(not pcall(wide.decode_into,packet,old))
for _,value in old do assert(value==false,"semantic error changed wide baseline") end

for _,count in {1,40} do
	local fields,baseline,current={},{},{}
	for i=1,count do
		fields[i]=S.field(tostring(i),S.quantized(0,1,8))
		baseline[tostring(i)]=0.5
		current[tostring(i)]=0.5001
	end
	local codec=S.delta(S.object(fields))
	assert(buffer.len(codec.encode(baseline,current))==math.ceil(count/8),"sent unchanged quantized codes")
	current["1"]=1.0001
	assert(not pcall(codec.encode,baseline,current),"merged invalid quantized value")
end

print(`Delta tests: {cases} changes passed across mask boundaries`)

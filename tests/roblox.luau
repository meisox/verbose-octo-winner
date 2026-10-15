local S = require("./.generated/src/index")
local r = if game then {Vector2=Vector2,Vector3=Vector3,CFrame=CFrame,Color3=Color3,UDim=UDim,UDim2=UDim2}
	else require("@lune/roblox")
local V2,V3,CF,Color,U,U2 = r.Vector2,r.Vector3,r.CFrame,r.Color3,r.UDim,r.UDim2
local function throws(callback) assert(not pcall(callback), "expected rejection") end
local state = 48271
local function random()
	state = (state * 1664525 + 1013904223) % 4294967296
	return state / 4294967296
end
local function angular_distance(a,b)
	local ac,bc = {a:GetComponents()},{b:GetComponents()}
	local squared=0
	for i=4,12 do squared += (ac[i]-bc[i])^2 end
	return 2 * math.asin(math.min(1,math.sqrt(squared) / (2 * math.sqrt(2))))
end
local function packet(codec,value)
	local bytes = S.encode(codec,value)
	local dirty = buffer.fromstring(string.rep("\255", codec.size + 6))
	S.into(codec,dirty,3,value)
	assert(buffer.readstring(dirty,3,codec.size) == buffer.tostring(bytes), "dirty writer differs")
	assert(buffer.readu8(dirty,2)==255 and buffer.readu8(dirty,codec.size+3)==255)
	return bytes,S.from(codec,dirty,3)
end
local vector_cases=0
for bits=2,32 do
	for _,dimension in {2,3} do
		local vector = if dimension==2 then V2 else V3
		local extent = if dimension==2 then V2.new(1000,13) else V3.new(1000,13,0.0625)
		local codec = if dimension==2 then S.quantized_vector2(extent,bits) else S.quantized_vector3(extent,bits)
		assert(codec.size==math.ceil(dimension*bits/8))
		local zero = vector.new()
		assert(S.decode(codec,S.encode(codec,zero))==zero,"zero must be exact")
		for index=1,38 do
			local multiplier = if index==1 then 1 elseif index==2 then -1 else 2*random()-1
			local value = if dimension==2 then V2.new(extent.X*multiplier,extent.Y*multiplier)
				else V3.new(extent.X*multiplier,extent.Y*multiplier,extent.Z*multiplier)
			local bytes,decoded=packet(codec,value)
			assert(math.abs(value.X-decoded.X)<=codec.max_error.X,"x error bound")
			assert(math.abs(value.Y-decoded.Y)<=codec.max_error.Y,"y error bound")
			if dimension==3 then assert(math.abs(value.Z-decoded.Z)<=codec.max_error.Z,"z error bound") end
			-- Independent bit reader checks the wire without native bit accessors.
			for axis=1,dimension do
				local code=0
				for bit=0,bits-1 do
					local at=(axis-1)*bits+bit
					code+=math.floor(buffer.readu8(bytes,math.floor(at/8))/2^(at%8))%2*2^bit
				end
				local component = if axis==1 then value.X elseif axis==2 then value.Y else value.Z
				local bound = if axis==1 then extent.X elseif axis==2 then extent.Y else extent.Z
				local expected = math.round(component*((2^(bits-1)-1)/bound))
				assert(code==expected%2^bits,"signed vector wire layout")
			end
			vector_cases+=1
		end
		local invalid=buffer.create(codec.size)
		buffer.writebits(invalid,0,bits,2^(bits-1))
		throws(function() S.decode(codec,invalid) end)
		local padding=codec.size*8-dimension*bits
		if padding>0 then
			invalid=S.encode(codec,zero)
			buffer.writebits(invalid,dimension*bits,padding,1)
			throws(function() S.decode(codec,invalid) end)
		end
		throws(function() S.encode(codec,vector.new(math.huge,0,0)) end)
		throws(function() S.encode(codec,vector.new(1001,0,0)) end)
	end
	if game and bits%8==0 then task.wait() end
end
for _,bits in {0,1,33,0.5,0/0,math.huge} do throws(function() S.quantized_vector3(1,bits) end) end
for _,extent in {0,-1,0/0,math.huge} do throws(function() S.quantized_vector3(extent,10) end) end
throws(function() S.quantized_vector3(V3.new(1,0,1),10) end)
for _,extent in {1e-40,1e-35,1e-30,1e-4,1e30,3e38} do
	for _,bits in {4,10,24,32} do
		if V3.new(extent,extent,extent).X == 0 then
			throws(function() S.quantized_vector3(extent,bits) end)
			continue
		end
		local codec=S.quantized_vector3(extent,bits)
		for _,scale in {-1,-0.12345,0,0.12345,1} do
			local value=V3.new(codec.max_abs.X*scale,0,0)
			local decoded=S.decode(codec,S.encode(codec,value))
			assert(math.abs(value.X-decoded.X)<=codec.max_error.X,"float32 extreme vector error bound")
		end
		if extent>=2^-126 then
			local value=V3.new(2^-126,0,0)
			local decoded=S.decode(codec,S.encode(codec,value))
			assert(math.abs(value.X-decoded.X)<=codec.max_error.X,"float32 normal/subnormal boundary error")
		end
	end
end
for _,case in {{S.vector2_5,V2.new(0,100000),0.1},{S.vector2_8,V2.new(3.25,-7.5),0},
	{S.vector3_8,V3.new(-100000,0,100000),0.055},{S.vector3_12,V3.new(3.25,-7.5,19),0}} do
	local _,decoded=packet(case[1],case[2]);assert((decoded-case[2]).Magnitude<=case[3])
end
for _,case in {{S.color3_3,Color.new(0.123,0.456,0.789),1/510},{S.color3_12,Color.new(0.125,0.5,1),0}} do
	local _,decoded=packet(case[1],case[2])
	assert(math.abs(decoded.R-case[2].R)<=case[3]+1e-7)
	assert(math.abs(decoded.G-case[2].G)<=case[3]+1e-7)
	assert(math.abs(decoded.B-case[2].B)<=case[3]+1e-7)
end
for _,case in {{S.udim_8,U.new(0.25,-2147483648)},{S.udim2_16,U2.new(0.25,-100,-0.5,2147483647)}} do
	local _,decoded=packet(case[1],case[2]);assert(decoded==case[2])
end
local rotation_cases=0
local position=S.quantized_vector3(V3.new(1000,13,0.0625),19)
for bits=4,20 do
	local codec=S.cframe(position,bits)
	assert(codec.size==position.size+math.ceil((2+3*bits)/8))
	for index=1,180 do
		local x,y,z,w=2*random()-1,2*random()-1,2*random()-1,2*random()-1
		if index<=4 then x,y,z,w=0,0,0,0;if index==1 then x=1 elseif index==2 then y=1 elseif index==3 then z=1 else w=1 end end
		if index==5 then x,y,z,w=0.5,0.5,0.5,0.5 end
		local inverse=1/math.sqrt(x*x+y*y+z*z+w*w)
		local value=CF.new((random()-0.5)*1000,(random()-0.5)*13,(random()-0.5)*0.0625,x*inverse,y*inverse,z*inverse,w*inverse)
		local _,decoded=packet(codec,value)
		local angle=angular_distance(value,decoded)
		assert(angle<=codec.angular_error,`rotation bound at {bits} bits: {angle} > {codec.angular_error}`)
		assert(math.abs(decoded.X-value.X)<=position.max_error.X)
		assert(math.abs(decoded.Y-value.Y)<=position.max_error.Y)
		assert(math.abs(decoded.Z-value.Z)<=position.max_error.Z)
		for _,preset in {S.cframe_12,S.cframe_16,S.cframe_28,S.cframe_48} do
			local _,readback=packet(preset,value)
			assert(angular_distance(value,readback)<(if preset==S.cframe_12 then 0.0025 elseif preset==S.cframe_16 then 0.005 else 2e-6))
		end
		rotation_cases+=1
	end
	local invalid=buffer.create(codec.size)
	local start=position.size*8
	buffer.writebits(invalid,start+2,bits,2^bits-1)
	buffer.writebits(invalid,start+2+bits,bits,2^bits-1)
	buffer.writebits(invalid,start+2+2*bits,bits,2^bits-1)
	throws(function() S.decode(codec,invalid) end)
	local padding=(codec.size-position.size)*8-2-3*bits
	if padding>0 then
		invalid=S.encode(codec,CF.new())
		buffer.writebits(invalid,start+2+3*bits,padding,1)
		throws(function() S.decode(codec,invalid) end)
	end
	if game then task.wait() end
end
assert(S.cframe_16.size==16)
for _,bits in {0,3,21,4.5,0/0,math.huge} do throws(function() S.cframe(S.vector3_12,bits) end) end
for _,matrix in {{2,0,0,0,1,0,0,0,1},{-1,0,0,0,1,0,0,0,1},{0,0,0,0,0,0,0,0,0}} do
	local value=CF.new(0,0,0,unpack(matrix))
	for _,codec in {S.cframe_12,S.cframe_16,S.cframe_28} do throws(function() S.encode(codec,value) end) end
	packet(S.cframe_48,value)
end
for _,quaternion in {{0,0,0,0},{0,0,0,2},{0,0,0,-1},{0/0,0,0,1}} do
	local invalid=buffer.create(28)
	for i=1,4 do buffer.writef32(invalid,8+i*4,quaternion[i]) end
	throws(function() S.decode(S.cframe_28,invalid) end)
end
local invalid=buffer.fromstring(string.rep("\255",12))
buffer.writebits(invalid,95,1,0)
throws(function() S.decode(S.cframe_12,invalid) end)
print(`Roblox tests: {vector_cases} vector wire/precision cases and {rotation_cases} rotations passed; all datatype presets and invalid rotations checked`)

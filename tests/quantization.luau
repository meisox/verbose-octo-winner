local S=require("./.generated/src/index")
local intervals={
	{-10,10},{0,1},{-100000,100000},{-1e308,1e308},{0,1.7976931348623157e308},
	{-1.7976931348623157e308,0},{1e300,1.0001e300},{0,1e-300},{-1e-300,1e-300},
	{0,1e-310},{-1e-310,0},{-1e-310,1e-310},{0,5e-324},{-5e-324,5e-324},
	{1,1.0000000000000002},
}
local cases=0
for _,interval in intervals do
	local lo,hi=interval[1],interval[2]
	local span=hi-lo
	for width=1,32 do
		local codec=S.quantized(lo,hi,width)
		local previous=lo
		for i=0,100 do
			local fraction=i/100
			local interpolated=if math.isfinite(span) then lo+span*fraction else (1-fraction)*lo+fraction*hi
			local value=if i==0 then lo elseif i==100 then hi else math.clamp(interpolated,lo,hi)
			local packet=S.encode(codec,value)
			local decoded=S.decode(codec,packet)
			assert(math.isfinite(decoded) and decoded>=lo and decoded<=hi,`out of bounds for [{lo}, {hi}]/{width}: {decoded}`)
			assert(decoded>=previous,`nonmonotonic [{lo}, {hi}]/{width}`)
			if i==0 then assert(decoded==lo,`minimum [{lo}, {hi}]/{width}`) end
			if i==100 then assert(decoded==hi,`maximum [{lo}, {hi}]/{width}`) end
			previous=decoded
			cases+=1
		end
		-- Decode known wire codes as well: engine arithmetic can flush generated
		-- subnormal input samples to zero before they ever reach the encoder.
		previous=lo
		local raw=buffer.create(codec.size)
		for i=0,100 do
			buffer.writebits(raw,0,codec.size*8,math.floor((2^width-1)*i/100))
			local decoded=S.decode(codec,raw)
			assert(math.isfinite(decoded) and decoded>=lo and decoded<=hi)
			assert(decoded>=previous,`nonmonotonic wire codes [{lo}, {hi}]/{width}`)
			previous=decoded
			cases+=1
		end
		if width % 4 == 0 and task then task.wait() end
	end
end
for _,bits in {0,33,1.5,math.huge,0/0} do assert(not pcall(S.quantized,0,1,bits)) end
assert(not pcall(S.quantized,1,1,8))
assert(not pcall(S.encode,S.quantized(0,1,12),1.01))
assert(not pcall(S.encode,S.quantized(0,1,12),0/0))
print(`Quantization tests: {cases} values passed across all widths and floating-point extremes`)

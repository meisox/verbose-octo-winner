-- Stage the baseline with: node scripts/prepare-tests.cjs --ref 0327edf
-- Then run: luau -O2 [--codegen] benchmarks/compare.luau
local old = {
	bits=require("../tests/.baseline/src/Primitive/bits"),
	quantized=require("../tests/.baseline/src/Composite/quantized"),
	packed=require("../tests/.baseline/src/Composite/packed"),
	array=require("../tests/.baseline/src/Composite/array"),
	u8=require("../tests/.baseline/src/Primitive/u8"),
	u16=require("../tests/.baseline/src/Primitive/u16"),
	u32=require("../tests/.baseline/src/Primitive/u32"),
}
local new = {
	bits=require("../src/Primitive/bits"),
	quantized=require("../src/Composite/quantized"),
	packed=require("../src/Composite/packed"),
	array=require("../src/Composite/array"),
	u8=require("../src/Primitive/u8"),
	u16=require("../src/Primitive/u16"),
	u32=require("../src/Primitive/u32"),
}
local function trial(codec,value,iterations,operation)
	local data=buffer.create(codec.size)
	codec.write(data,0,value)
	local output=codec.read(data,0)
	local start=os.clock()
	if operation=="write" then
		for _=1,iterations do codec.write(data,0,value) end
	else
		for _=1,iterations do output=codec.read(data,0,output) end
	end
	return (os.clock()-start)*1e9/iterations
end
local function bench(name,build,value,iterations)
	local before,after=build(old),build(new)
	for _,op in {"write","read_reuse"} do
		local a,b={},{}
		for round=1,11 do
			local x,y
			if round%2==0 then x=trial(before,value,iterations,op);y=trial(after,value,iterations,op)
			else y=trial(after,value,iterations,op);x=trial(before,value,iterations,op) end
			if round>2 then table.insert(a,x);table.insert(b,y) end
		end
		table.sort(a);table.sort(b)
		print(string.format("%s,%s,%d,%d,%.1f,%.1f,%.3f",name,op,before.size,after.size,a[5],b[5],b[5]/a[5]))
	end
end
print("case,operation,old_bytes,new_bytes,old_ns,new_ns,new_over_old")
bench("u8",function(s)return s.u8 end,127,200000)
bench("bits20",function(s)return s.bits(20)end,500000,200000)
bench("quantized16",function(s)return s.quantized(-10,10,16)end,1.25,200000)
bench("packed24",function(s)return s.packed({{name="a",codec=s.bits(12)},{name="b",codec=s.bits(12)}})end,{a=1023,b=2049},100000)
for _,name in {"u8","u16","u32"} do
	bench("array_"..name.."_256",function(s)return s.array(s[name],256)end,table.create(256,127),10000)
end

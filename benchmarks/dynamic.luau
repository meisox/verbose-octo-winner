-- Run after staging both trees with scripts/prepare-tests.cjs.
local old={
	d=require("../tests/.baseline/src/Dynamic/index"),
	u8=require("../tests/.baseline/src/Primitive/u8"),
	u32=require("../tests/.baseline/src/Primitive/u32"),
}
local new={
	d=require("../tests/.generated/src/Dynamic/index"),
	u8=require("../src/Primitive/u8"),
	u32=require("../src/Primitive/u32"),
}
local function trial(profile,codec,value,iterations,operation)
	local data=profile.d.encode(codec,value)
	local output=profile.d.decode(codec,data)
	local start=os.clock()
	if operation=="encode" then
		for _=1,iterations do data=profile.d.encode(codec,value) end
	else
		for _=1,iterations do output=profile.d.decode_into(codec,data,output) end
	end
	return (os.clock()-start)*1e9/iterations
end
local function bench(name,build,value,iterations)
	local before,after=build(old),build(new)
	for _,op in {"encode","decode_reuse"} do
		local a,b={},{}
		for round=1,9 do
			local x,y
			if round%2==0 then x=trial(old,before,value,iterations,op);y=trial(new,after,value,iterations,op)
			else y=trial(new,after,value,iterations,op);x=trial(old,before,value,iterations,op) end
			if round>2 then table.insert(a,x);table.insert(b,y) end
		end
		table.sort(a);table.sort(b)
		print(string.format("%s,%s,%d,%d,%.1f,%.1f,%.3f",name,op,before.measure(value),after.measure(value),a[4],b[4],b[4]/a[4]))
	end
end
print("case,operation,old_bytes,new_bytes,old_ns,new_ns,new_over_old")
bench("varu32",function(s)return s.d.varu32 end,1000,50000)
bench("string_12",function(s)return s.d.string(64)end,"hello world!",50000)
bench("string_large_max",function(s)return s.d.string(100000)end,"hello world!",50000)
for _,n in {8,256,10000} do
	for _,name in {"u8","u32"} do
		bench(`array_{name}_{n}`,function(s)return s.d.array(s.d.fixed(s[name]),10000)end,table.create(n,100),if n==10000 then 100 else 3000)
	end
end
bench("object",function(s)return s.d.object({
	{name="id",codec=s.d.fixed(s.u32)},
	{name="name",codec=s.d.string(64)},
	{name="items",codec=s.d.array(s.d.fixed(s.u32),1000)},
})end,{id=1,name="Player",items=table.create(100,100)},3000)
bench("rle_256",function(s)return s.d.rle(s.d.fixed(s.u8),1000)end,table.create(256,100),3000)
local sorted={}
for i=1,256 do sorted[i]=i*100 end
bench("delta_array_256",function(s)return s.d.delta_array(1000)end,sorted,3000)

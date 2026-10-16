-- Engine-only paired workloads. Called by build-studio-benchmark.cjs.
return function(old,new)
	local rows={}
	local function trial(s,codec,value,iterations,operation,dynamic)
		local api=if dynamic then s.dynamic else s
		local bytes=api.encode(codec,value)
		local output=api.decode(codec,bytes)
		local start=os.clock()
		if operation=="encode" then
			for _=1,iterations do bytes=api.encode(codec,value) end
		elseif operation=="unsafe_encode" then
			for _=1,iterations do bytes=api.unsafe_encode(codec,value) end
		else
			for _=1,iterations do output=api.decode_into(codec,bytes,output) end
		end
		return (os.clock()-start)*1e9/iterations
	end
	local function bench(name,build,value,iterations,dynamic)
		local before,after=build(old),build(new)
		for _,operation in {"encode","decode_reuse"} do
			local a,b={},{}
			for round=1,9 do
				local x,y
				if round%2==0 then
					x=trial(old,before,value,iterations,operation,dynamic);y=trial(new,after,value,iterations,operation,dynamic)
				else
					y=trial(new,after,value,iterations,operation,dynamic);x=trial(old,before,value,iterations,operation,dynamic)
				end
				if round>2 then table.insert(a,x);table.insert(b,y) end
				task.wait()
			end
			table.sort(a);table.sort(b)
			table.insert(rows,{name=name,operation=operation,old_ns=a[4],new_ns=b[4],ratio=b[4]/a[4],
				old_bytes=if dynamic then before.measure(value) else before.size,
				new_bytes=if dynamic then after.measure(value) else after.size})
		end
	end
	bench("packed24",function(s)return s.packed({s.field("a",s.bits(12)),s.field("b",s.bits(12))})end,{a=1023,b=2049},10000)
	bench("snapshot",function(s)return s.object({s.field("tick",s.u32),s.field("health",s.range(0,100)),s.field("position",s.vector3_12),s.field("flags",s.bits(5))})end,
		{tick=1000,health=87,position=Vector3.new(100,25,-50),flags=3},10000)
	bench("fixed_u32_256",function(s)return s.array(s.u32,256)end,table.create(256,100),1000)
	bench("dynamic_u32_256",function(s)return s.dynamic.array(s.dynamic.fixed(s.u32),1000)end,table.create(256,100),1000,true)
	bench("dynamic_record",function(s)return s.dynamic.object({
		{name="id",codec=s.dynamic.fixed(s.u32)},{name="name",codec=s.dynamic.string(64)},
		{name="items",codec=s.dynamic.array(s.dynamic.fixed(s.u32),1000)},
	})end,{id=1,name="Player",items=table.create(100,100)},1000,true)
	bench("rle_256",function(s)return s.dynamic.rle(s.dynamic.fixed(s.u8),1000)end,table.create(256,100),1000,true)
	bench("varu32",function(s)return s.dynamic.varu32 end,1000,20000,true)
	bench("string_12",function(s)return s.dynamic.string(64)end,"hello world!",20000,true)
	local transform=CFrame.new(100,25,-50)*CFrame.Angles(0.5,1.25,-0.75)
	for _,name in {"cframe_12","cframe_28","cframe_48"} do bench(name,function(s)return s[name]end,transform,10000) end
	local codec=new.cframe_16
	local new_only={name="cframe_16",bytes=codec.size,angular_error_degrees=math.deg(codec.angular_error)}
	for _,operation in {"encode","unsafe_encode","decode_reuse"} do
		local times={}
		for round=1,9 do
			local elapsed=trial(new,codec,transform,10000,operation,false)
			if round>2 then table.insert(times,elapsed) end
			task.wait()
		end
		table.sort(times);new_only[operation.."_ns"]=times[4]
	end
	return {version=version(),rows=rows,new_codec=new_only,trials=7,warmups=2}
end

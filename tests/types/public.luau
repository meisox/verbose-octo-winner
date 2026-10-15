--!strict
local S = require("../../src")
local position = S.quantized_vector3(Vector3.new(2048,512,2048),18)
local state = S.struct({id=S.u32,transform=S.cframe(position),alive=S.bool})
type State = S.Infer<typeof(state)>
local value: State = {id=123,transform=CFrame.new(),alive=true}
local packet = S.encode(state,value)
local decoded = S.decode(state,packet)
local _transform: CFrame = decoded.transform
local _alive: boolean = decoded.alive
local dynamic = S.dynamic.struct({name=S.dynamic.string(100),state=state})
local data = S.dynamic.encode(dynamic,{name="name",state=value})
local _name: string = S.dynamic.decode(dynamic,data).name
local batch = S.decode_many(S.optional(S.u8),buffer.create(4))
local _length: number? = batch.n
local compressed = S.compressed.encode(dynamic,{name="name",state=value})
local _compressed_name: string = S.compressed.decode(dynamic,compressed).name
local _adaptive_name: string = S.compressed.adaptive.decode(dynamic,compressed).name
local _optional: number? = S.decode(S.optional(S.u8),buffer.create(2))
local _batch_item: number? = batch[1]

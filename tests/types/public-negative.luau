--!strict
local S=require("../../src")
local schema=S.struct({id=S.u8,enabled=S.bool})
local packet=buffer.create(schema.size)
local decoded=S.decode(schema,packet)
local _wrong: string=decoded.id -- EXPECT_ERROR
S.encode(schema,{id="bad",enabled=true}) -- EXPECT_ERROR
S.decode_into(schema,packet,{id=1,enabled="bad"}) -- EXPECT_ERROR
local optional=S.decode(S.optional(S.u8),buffer.create(2))
local _nonnullable: number=optional -- EXPECT_ERROR
local dynamic=S.dynamic.struct({name=S.dynamic.string(10)})
local _wrong_dynamic: number=S.dynamic.decode(dynamic,buffer.create(1)).name -- EXPECT_ERROR
local _wrong_compressed: number=S.compressed.decode(dynamic,buffer.create(1)).name -- EXPECT_ERROR
local _wrong_adaptive: number=S.compressed.adaptive.decode(dynamic,buffer.create(1)).name -- EXPECT_ERROR
S.cframe(S.u8) -- EXPECT_ERROR

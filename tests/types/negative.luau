--!strict
-- Each EXPECT_ERROR line must be rejected by luau-analyze.
local struct = require("../../src/Composite/struct")
local u8 = require("../../src/Primitive/u8")
local text = require("../../src/Composite/string")
local codec = struct({id=u8,name=text(20)})
local value = codec.read(buffer.create(codec.size),0)
local _wrong: string = value.id -- EXPECT_ERROR
local _missing = value.no_such_field -- EXPECT_ERROR
codec.write(buffer.create(codec.size),0,{id="wrong",name="x"}) -- EXPECT_ERROR
codec.write(buffer.create(codec.size),0,{id=1}) -- EXPECT_ERROR
local union=require("../../src/Dynamic/union")
local dynamic_string=require("../../src/Dynamic/string")
local choice=union({message=dynamic_string(64),count=u8})
choice.measure({tag="message",value=1}) -- EXPECT_ERROR
choice.measure({tag="unknown",value=1}) -- EXPECT_ERROR
local selected=choice.read(buffer.create(100),0)
if selected.tag=="message" then
	local _wrong_payload: number=selected.value -- EXPECT_ERROR
end

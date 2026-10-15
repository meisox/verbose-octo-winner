--!strict
local Types = require("../../src/Types")
local struct = require("../../src/Composite/struct")
local packed_struct = require("../../src/Composite/packed_struct")
local u8 = require("../../src/Primitive/u8")
local boolean = require("../../src/Primitive/bool")
local text = require("../../src/Composite/string")
local array = require("../../src/Composite/array")
local optional = require("../../src/Composite/optional")
local range = require("../../src/Composite/range")

local player = struct({
	id = u8,
	name = text(20),
	state = packed_struct({alive = boolean, health = range(0,100)}),
	tags = array(text(10),2),
	target = optional(u8),
})
type Player = Types.Infer<typeof(player)>
local value: Player = {id=1,name="Hi",state={alive=true,health=50},tags={"a","b"},target=nil}
local packet = buffer.create(player.size)
player.write(packet,0,value)
local result = player.read(packet,0)
local _id: number = result.id
local _name: string = result.name
local _alive: boolean = result.state.alive
local _tag: string = result.tags[1]
local _target: number? = result.target

local dynamic_struct = require("../../src/Dynamic/struct")
local dynamic_string = require("../../src/Dynamic/string")
local dynamic_array = require("../../src/Dynamic/array")
local dynamic_union = require("../../src/Dynamic/union")
local dynamic_map = require("../../src/Dynamic/map")
local dynamic_optional = require("../../src/Dynamic/optional")
local stored=dynamic_struct({id=u8,name=dynamic_string(64),tags=dynamic_array(u8,10),target=dynamic_optional(u8)})
type Stored = Types.Infer<typeof(stored)>
local stored_value: Stored = {id=1,name="name",tags={1,2},target=nil}
local _size: number=stored.measure(stored_value)
local stored_result=stored.read(buffer.create(100),0)
local _stored_name: string=stored_result.name
local _stored_target: number?=stored_result.target
local choice=dynamic_union({message=dynamic_string(64),count=u8})
local selected=choice.read(buffer.create(100),0)
if selected.tag=="message" then
	local _message: string=selected.value
else
	local _count: number=selected.value
end
choice.measure({tag="message",value="hello"})
choice.measure({tag="count",value=12})
local mapping=dynamic_map(dynamic_string(10),u8,100)
local map_result=mapping.read(buffer.create(100),0)
local _mapped: number=map_result["key"]

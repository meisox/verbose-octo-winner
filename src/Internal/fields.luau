--!strict

local Types = require("../Types")
local schema_list = require("./schema_list")

-- Explicit order is optional. The default is lexicographic, never hash order.
return function(schema: {[string]: any}, order: {string}?): {Types.Field<any>}
	if type(schema) ~= "table" then error("Serdes.struct expected a table of named codecs") end
	local names: {string} = {}
	for name in schema do
		if type(name) ~= "string" or name == "" then error("Serdes.struct expected nonempty string field names") end
		table.insert(names, name)
	end
	if order == nil then
		table.sort(names)
	else
		schema_list(order, "struct order")
		if #order ~= #names then error("Serdes.struct order must contain every field exactly once") end
		names = table.clone(order)
	end
	local fields = table.create(#names) :: {Types.Field<any>}
	local seen = {}
	for index, name in names do
		local codec = schema[name]
		if seen[name] or codec == nil then error(`Serdes.struct invalid or repeated field '{name}' in order`) end
		if type(codec) ~= "table" or type(codec.read) ~= "function" then error(`Serdes.struct field '{name}' is not a codec`) end
		seen[name] = true
		fields[index] = { name = name, codec = codec }
	end
	return fields
end

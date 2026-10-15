--!strict

local Types = require("../Types")
local fields = require("../Internal/fields")
local packed = require("./packed")

return function<S>(schema: S, order: {string}?): Types.Codec<Types.Shape<S>>
	return packed(fields(schema :: any, order)) :: any
end

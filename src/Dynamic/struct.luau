--!strict

local Types = require("../Types")
local fields = require("../Internal/fields")
local object = require("./object")

return function<S>(schema: S, order: {string}?): Types.DynamicCodec<Types.Shape<S>>
	return object(fields(schema :: any, order) :: any) :: any
end

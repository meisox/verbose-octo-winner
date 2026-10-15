--!strict
local Types = require("../../src/Types")
local struct = require("../../src/Composite/struct")
local union = require("../../src/Dynamic/union")
local u8 = require("../../src/Primitive/u8")
local runtime_schema: {[string]: Types.Codec<number>} = {id=u8}
local record = struct(runtime_schema) -- EXPECT_ERROR
local variant = union(runtime_schema) -- EXPECT_ERROR

--!strict

-- Only used while constructing a schema; runtime data keeps its bulk paths.
return function(value: {any}, name: string): number
	if type(value) ~= "table" then error(`Serdes.{name} expected a dense schema list`) end
	local count, present = #value, 0
	for index in value do
		if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > count then
			error(`Serdes.{name} expected consecutive schema indices starting at one`)
		end
		present += 1
	end
	if present ~= count then error(`Serdes.{name} schema cannot contain holes`) end
	return count
end

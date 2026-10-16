--!strict

-- Nullable fixed sequences have their length in the schema, since Lua tables
-- cannot represent trailing nils. Only those schemas need the sparse-key scan.
return function(count: number, nullable: boolean, name: string): (value: {any}) -> ()
	if nullable then
		return function(value: {any}): ()
			if type(value) ~= "table" then
				error(`Serdes.{name} expected table, got {typeof(value)}`, 3)
			end
			for key in value do
				if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > count then
					error(`Serdes.{name} expected indices in [1, {count}], got {key}`, 3)
				end
			end
		end
	end
	return function(value: {any}): ()
		if type(value) ~= "table" then
			error(`Serdes.{name} expected table, got {typeof(value)}`, 3)
		end
		if #value ~= count then
			error(`Serdes.{name} expected exactly {count} elements, got {#value}`, 3)
		end
	end
end

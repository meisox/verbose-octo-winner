--!strict
--!native

return function(maximum: number, nullable: boolean, name: string)
	return function(value: {[number]: any, n: number?}): number
		if type(value) ~= "table" then error(`Serdes.{name} expected an array table`) end
		local count: number
		if nullable then
			local explicit = value.n
			if type(explicit) ~= "number" or explicit % 1 ~= 0 or explicit < 0 then
				error(`Serdes.{name} with nullable elements requires an explicit 'n' length; use table.pack`)
			end
			count = explicit
			for key in value :: any do
				if key ~= "n" and (type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > count) then
					error(`Serdes.{name} invalid array index {key}`)
				end
			end
		else
			count = #value
		end
		if count > maximum then error(`Serdes.{name} expected at most {maximum} elements, got {count}`) end
		return count
	end
end

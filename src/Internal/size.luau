--!strict
--!native

return function(size: number): number
	if type(size) ~= "number" or size % 1 ~= 0 or size < 0 or size > 1_073_741_824 then
		error(`Serdes encoded size must be an integer in [0, 1073741824], got {size}`, 3)
	end
	return size
end

--!strict

return function(maximum: number): number
	local bits = 0

	while maximum > 0 do
		bits += 1
		maximum //= 2
	end

	return bits
end

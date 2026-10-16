--!strict

return function(extent: number, bits: number): (number, number, number)
	if type(bits) ~= "number" or bits % 1 ~= 0 or bits < 2 or bits > 32 then
		error(`Serdes quantized vectors require an integer bit count in [2, 32], got {bits}`)
	end
	if not math.isfinite(extent) or extent <= 0 then
		error(`Serdes quantized vector extent must be finite and positive, got {extent}`)
	end
	local maximum = 2 ^ (bits - 1) - 1
	local step = extent / maximum
	-- Half a grid step plus conservative float32 reconstruction rounding.
	-- The small margin also rounds the exposed Vector2/3 bound upward.
	-- Roblox may flush subnormal float32 components to zero. Include that
	-- absolute error as well as ordinary output rounding and grid rounding.
	local error_bound = (step * 0.5 + extent * 2 ^ -24 + 2 ^ -126) * (1 + 2 ^ -20)
	return maximum / extent, step, error_bound
end

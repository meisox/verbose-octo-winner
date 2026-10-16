--!strict
--!native

-- Quaternion codecs require a proper rotation. Raw matrix codecs need not.
return function(
	a: number, b: number, c: number,
	d: number, e: number, f: number,
	g: number, h: number, i: number
): ()
	local tolerance = 0.001
	if not math.isfinite(a + b + c + d + e + f + g + h + i)
		or math.abs(a*a + b*b + c*c - 1) > tolerance
		or math.abs(d*d + e*e + f*f - 1) > tolerance
		or math.abs(g*g + h*h + i*i - 1) > tolerance
		or math.abs(a*d + b*e + c*f) > tolerance
		or math.abs(a*g + b*h + c*i) > tolerance
		or math.abs(d*g + e*h + f*i) > tolerance
		or a*(e*i - f*h) - b*(d*i - f*g) + c*(d*h - e*g) <= 0 then
		error("Serdes expected a proper orthonormal CFrame rotation")
	end
end

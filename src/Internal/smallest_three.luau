--!strict
--!native

-- Each retained quaternion component is rounded with error <= step/2.
-- The omitted (largest) component has magnitude >= 1/2. These bounds
-- include ties and give necessary validity checks for the rounded triple.
return function(step: number): ((number, number, number) -> number, number)
	local squared_error = 1.5 * step + 0.75 * step * step
	local omitted_error = squared_error / (0.5 + math.sqrt(0.25 - squared_error))
	local largest_tolerance = step * 0.5 + omitted_error + 1e-12
	local squared_limit = 0.75 + squared_error + 1e-12
	local distance = math.sqrt(0.75 * step * step + omitted_error * omitted_error)
	local angular_error = 4 * math.asin(math.min(1, distance * 0.5)) + 2e-6
	local function checked_omitted(a: number, b: number, c: number): number
		local squared = a*a + b*b + c*c
		if squared > squared_limit then error("Serdes decoded impossible quaternion components") end
		local omitted = math.sqrt(1 - squared)
		if math.max(math.abs(a), math.abs(b), math.abs(c)) > omitted + largest_tolerance then
			error("Serdes decoded quaternion omitted component is not largest")
		end
		return omitted
	end
	return checked_omitted, angular_error
end

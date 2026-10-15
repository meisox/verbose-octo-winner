--!strict
--!native

local function raw_matrix_to_quaternion(
	r00: number,
	r01: number,
	r02: number,
	r10: number,
	r11: number,
	r12: number,
	r20: number,
	r21: number,
	r22: number
): (number, number, number, number)
	local trace = r00 + r11 + r22

	if trace > 0 then
		local s = math.sqrt(trace + 1)
		local inverse = 0.5 / s

		return (r21 - r12) * inverse, (r02 - r20) * inverse, (r10 - r01) * inverse, 0.5 * s
	elseif r00 > r11 and r00 > r22 then
		local s = math.sqrt(1 + r00 - r11 - r22)
		local inverse = 0.5 / s

		return 0.5 * s, (r01 + r10) * inverse, (r02 + r20) * inverse, (r21 - r12) * inverse
	elseif r11 > r22 then
		local s = math.sqrt(1 + r11 - r00 - r22)
		local inverse = 0.5 / s

		return (r01 + r10) * inverse, 0.5 * s, (r12 + r21) * inverse, (r02 - r20) * inverse
	else
		local s = math.sqrt(1 + r22 - r00 - r11)
		local inverse = 0.5 / s

		return (r02 + r20) * inverse, (r12 + r21) * inverse, 0.5 * s, (r10 - r01) * inverse
	end
end

local function matrix_to_quaternion(
	r00: number, r01: number, r02: number,
	r10: number, r11: number, r12: number,
	r20: number, r21: number, r22: number
): (number, number, number, number)
	local x, y, z, w = raw_matrix_to_quaternion(r00, r01, r02, r10, r11, r12, r20, r21, r22)
	local inverse = 1 / math.sqrt(x*x + y*y + z*z + w*w)
	return x * inverse, y * inverse, z * inverse, w * inverse
end

local function choose_smallest_three(qx: number, qy: number, qz: number, qw: number): (number, number, number, number)
	local ax = math.abs(qx)
	local ay = math.abs(qy)
	local az = math.abs(qz)
	local aw = math.abs(qw)

	local index = 0
	local largest = ax

	if ay > largest then
		index = 1
		largest = ay
	end

	if az > largest then
		index = 2
		largest = az
	end

	if aw > largest then
		index = 3
	end

	local omitted = if index == 0 then qx elseif index == 1 then qy elseif index == 2 then qz else qw

	if omitted < 0 then
		qx = -qx
		qy = -qy
		qz = -qz
		qw = -qw
	end

	if index == 0 then
		return index, qy, qz, qw
	elseif index == 1 then
		return index, qx, qz, qw
	elseif index == 2 then
		return index, qx, qy, qw
	else
		return index, qx, qy, qz
	end
end

return table.freeze({
	matrix_to_quaternion = matrix_to_quaternion,
	choose_smallest_three = choose_smallest_three,
})

--!strict
--!native

return function(source: buffer, offset: number, size: number): ()
	if type(source) ~= "buffer" then
		error(`Serdes expected buffer, got {typeof(source)}`, 3)
	end
	if type(offset) ~= "number" or offset % 1 ~= 0 or offset < 0 or offset > buffer.len(source) - size then
		error(`Serdes region [{offset}, {offset + size}) is outside the buffer`, 3)
	end
end

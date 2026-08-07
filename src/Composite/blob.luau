--!strict
--!native

local Types = require("../Types")

type Codec<T> = Types.Codec<T>

local MAX_SIZE = 1_073_741_824

return function(size: number): Codec<buffer>
	if type(size) ~= "number" or not math.isfinite(size) or size % 1 ~= 0 or size < 0 or size > MAX_SIZE then
		error(`Serdes.blob expected a valid buffer size, got {size}`)
	end

	local function validate(value: buffer): ()
		if type(value) ~= "buffer" then
			error(`Serdes.blob({size}) expected buffer, got {typeof(value)}`)
		end

		local actual_size = buffer.len(value)

		if actual_size ~= size then
			error(`Serdes.blob({size}) expected exactly {size} bytes, got {actual_size}`)
		end
	end

	local function unsafe_write(target: buffer, offset: number, value: buffer): ()
		buffer.copy(target, offset, value, 0, size)
	end

	local function write(target: buffer, offset: number, value: buffer): ()
		if type(value) ~= "buffer" then
			error(`Serdes.blob({size}) expected buffer, got {typeof(value)}`)
		end

		local actual_size = buffer.len(value)

		if actual_size ~= size then
			error(`Serdes.blob({size}) expected exactly {size} bytes, got {actual_size}`)
		end

		buffer.copy(target, offset, value, 0, size)
	end

	local function read(source: buffer, offset: number, output: buffer?): buffer
		local result = if output == nil then buffer.create(size) else output

		buffer.copy(result, 0, source, offset, size)

		return result
	end

	return table.freeze({
		size = size,

		validate = validate,
		unsafe_write = unsafe_write,
		write = write,
		unsafe_write_fresh = unsafe_write,
		write_fresh = write,
		read = read,
		unsafe_read = read,
	})
end

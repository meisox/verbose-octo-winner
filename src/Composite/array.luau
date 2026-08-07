--!strict
--!native

local Types = require("../Types")

type Array<T> = Types.Array<T>
type Codec<T> = Types.Codec<T>
type ArrayWriter<T> = Types.ArrayWriter<T>
type ArrayReader<T> = Types.ArrayReader<T>

return function<T>(element: Codec<T>, count: number): Codec<Array<T>>
	if type(count) ~= "number" or not math.isfinite(count) or count % 1 ~= 0 or count < 0 then
		error(`Serdes.array expected a non-negative integer count, got {count}`)
	end

	local element_size = element.size

	if not math.isfinite(element_size) or element_size % 1 ~= 0 or element_size < 0 then
		error(`Serdes.array received codec with invalid size {element_size}`)
	end

	local SIZE = element_size * count

	if not math.isfinite(SIZE) then
		error("Serdes.array encoded size overflowed")
	end

	local element_validate = element.validate
	local element_unsafe_write = element.unsafe_write
	local element_write = element.write
	local element_unsafe_write_fresh = element.unsafe_write_fresh
	local element_write_fresh = element.write_fresh
	local element_read = element.read
	local element_unsafe_read = element.unsafe_read

	local array_unsafe_write = element.array_unsafe_write
	local array_write = element.array_write
	local array_unsafe_write_fresh = element.array_unsafe_write_fresh
	local array_write_fresh = element.array_write_fresh
	local array_read = element.array_read
	local array_unsafe_read = element.array_unsafe_read

	local function validate(value: Array<T>): ()
		if type(value) ~= "table" then
			error(`Serdes.array expected table, got {typeof(value)}`)
		end

		local actual_count = #value

		if actual_count ~= count then
			error(`Serdes.array expected exactly {count} elements, got {actual_count}`)
		end

		for index = 1, count do
			element_validate(value[index])
		end
	end

	local unsafe_write: (target: buffer, offset: number, value: Array<T>) -> ()
	local write: (target: buffer, offset: number, value: Array<T>) -> ()
	local unsafe_write_fresh: (target: buffer, offset: number, value: Array<T>) -> ()
	local write_fresh: (target: buffer, offset: number, value: Array<T>) -> ()
	local read: (source: buffer, offset: number, output: Array<T>?) -> Array<T>
	local unsafe_read: (source: buffer, offset: number, output: Array<T>?) -> Array<T>

	if array_unsafe_write ~= nil and array_write ~= nil and array_read ~= nil then
		local bulk_unsafe_write: ArrayWriter<T> = array_unsafe_write
		local bulk_write: ArrayWriter<T> = array_write
		local bulk_read: ArrayReader<T> = array_read

		unsafe_write = function(target: buffer, offset: number, value: Array<T>): ()
			bulk_unsafe_write(target, offset, value, count)
		end

		write = function(target: buffer, offset: number, value: Array<T>): ()
			if type(value) ~= "table" then
				error(`Serdes.array expected table, got {typeof(value)}`)
			end

			local actual_count = #value

			if actual_count ~= count then
				error(`Serdes.array expected exactly {count} elements, got {actual_count}`)
			end

			bulk_write(target, offset, value, count)
		end

		read = function(source: buffer, offset: number, output: Array<T>?): Array<T>
			return bulk_read(source, offset, count, output)
		end
	else
		unsafe_write = function(target: buffer, offset: number, value: Array<T>): ()
			local element_offset = offset

			for index = 1, count do
				element_unsafe_write(target, element_offset, value[index])
				element_offset += element_size
			end
		end

		write = function(target: buffer, offset: number, value: Array<T>): ()
			if type(value) ~= "table" then
				error(`Serdes.array expected table, got {typeof(value)}`)
			end

			local actual_count = #value

			if actual_count ~= count then
				error(`Serdes.array expected exactly {count} elements, got {actual_count}`)
			end

			local element_offset = offset

			for index = 1, count do
				element_write(target, element_offset, value[index])
				element_offset += element_size
			end
		end

		read = function(source: buffer, offset: number, output: Array<T>?): Array<T>
			local result: Array<T>

			if output == nil then
				result = table.create(count) :: Array<T>
			else
				result = output
			end

			local element_offset = offset

			for index = 1, count do
				result[index] = element_read(source, element_offset, result[index])
				element_offset += element_size
			end

			return result
		end
	end

	if array_unsafe_write_fresh ~= nil and array_write_fresh ~= nil then
		local bulk_unsafe_write_fresh: ArrayWriter<T> = array_unsafe_write_fresh
		local bulk_write_fresh: ArrayWriter<T> = array_write_fresh

		unsafe_write_fresh = function(target: buffer, offset: number, value: Array<T>): ()
			bulk_unsafe_write_fresh(target, offset, value, count)
		end

		write_fresh = function(target: buffer, offset: number, value: Array<T>): ()
			if type(value) ~= "table" then
				error(`Serdes.array expected table, got {typeof(value)}`)
			end

			local actual_count = #value

			if actual_count ~= count then
				error(`Serdes.array expected exactly {count} elements, got {actual_count}`)
			end

			bulk_write_fresh(target, offset, value, count)
		end
	else
		unsafe_write_fresh = function(target: buffer, offset: number, value: Array<T>): ()
			local element_offset = offset

			for index = 1, count do
				element_unsafe_write_fresh(target, element_offset, value[index])
				element_offset += element_size
			end
		end

		write_fresh = function(target: buffer, offset: number, value: Array<T>): ()
			if type(value) ~= "table" then
				error(`Serdes.array expected table, got {typeof(value)}`)
			end

			local actual_count = #value

			if actual_count ~= count then
				error(`Serdes.array expected exactly {count} elements, got {actual_count}`)
			end

			local element_offset = offset

			for index = 1, count do
				element_write_fresh(target, element_offset, value[index])
				element_offset += element_size
			end
		end
	end

	if array_unsafe_read ~= nil then
		local bulk_unsafe_read: ArrayReader<T> = array_unsafe_read

		unsafe_read = function(source: buffer, offset: number, output: Array<T>?): Array<T>
			return bulk_unsafe_read(source, offset, count, output)
		end
	else
		unsafe_read = function(source: buffer, offset: number, output: Array<T>?): Array<T>
			local result: Array<T>

			if output == nil then
				result = table.create(count) :: Array<T>
			else
				result = output
			end

			local element_offset = offset

			for index = 1, count do
				result[index] = element_unsafe_read(source, element_offset, result[index])
				element_offset += element_size
			end

			return result
		end
	end

	return table.freeze({
		size = SIZE,

		validate = validate,
		unsafe_write = unsafe_write,
		write = write,
		unsafe_write_fresh = unsafe_write_fresh,
		write_fresh = write_fresh,
		read = read,
		unsafe_read = unsafe_read,
	})
end

-- Author: Cheatoid ~ https://github.com/Cheatoid
-- License: MIT

-- Localized global functions for better performance
local assert = assert
local error = error
local next = next
local string_sub = string.sub
local table = require "@cheatoid/standard/table"
local table_concat = table.concat
local istype = require "@cheatoid/standalone/istype"
local isfunction = istype.isfunction
local isstring = istype.isstring
local istable = istype.istable
local bits = require "@cheatoid/standalone/bits"
local bits_double_to_uint32_high = bits.double_to_uint32_high
local bits_double_to_uint32_low = bits.double_to_uint32_low
local bits_bin64_to_double = bits.bin64_to_double
local bits_u32_to_bin32 = bits.u32_to_bin32
local bit = require "@cheatoid/standalone/bit"
local bit_pack_u8 = bit.pack_u8
local bit_unpack_u8 = bit.unpack_u8
local bit_pack_u16_le = bit.pack_u16_le
local bit_pack_le = bit.pack_le
local bit_unpack_u16_le = bit.unpack_u16_le
local bit_unpack_le = bit.unpack_le
local bit_pack_i8 = bit.pack_i8
local bit_pack_i16_le = bit.pack_i16_le
local bit_tounsigned = bit.tounsigned
local bit_tosigned = bit.tosigned
local bit_unpack_i8 = bit.unpack_i8
local bit_unpack_i16_le = bit.unpack_i16_le

local bit_band, bit_bor
if true then -- variadic switch (fold)
	bit_band = bit.band
	bit_bor = bit.bor
else
	bit_band = bits.band
	bit_bor = bits.bor
end
local bit_lshift = bits.lshift
local bit_rshift = bits.rshift

-- TODO: Optimize. Optimize. Optimize. (also use SlotMap)

-- Buffer system for binary I/O
local read_buffer = ""
local read_pos = 1
local write_buffer = {}
local write_count = 0

-- Bit accumulator for single-bit writes
local write_bit_accum = 0
local write_bit_pos = 0

-- Bit accumulator for single-bit reads
local read_bit_accum = 0
local read_bit_pos = 8

--- Reset the read buffer before starting a new read operation.<br>
--- Clears the read buffer, resets position, and bit accumulator.<br>
--- Call this before starting a new read sequence.
---@usage <br>
--- ```
--- net.resetReadBuffer()
--- net.setReadBuffer(new_data)
--- ```
local function reset_read_buffer()
	read_buffer = ""
	read_pos = 1
	read_bit_accum = 0
	read_bit_pos = 8
end

--- Reset the write buffer before starting a new write operation.<br>
--- Clears the write buffer, count, and bit accumulator.<br>
--- Call this before starting a new write sequence.
---@usage <br>
--- ```
--- net.resetWriteBuffer()
--- net.writeString("Hello")
--- ```
local function reset_write_buffer()
	write_buffer = {}
	write_count = 0
	write_bit_accum = 0
	write_bit_pos = 0
end

--- Set the read buffer with received data before reading.<br>
--- Resets the read position and bit accumulator to prepare for reading.<br>
--- Call this before any read operations with data received from network.<br>
---@param data string The binary data to read from.
---@usage <br>
--- ```
--- net.setReadBuffer(received_data)
--- local value = net.readInt(32)
--- ```
local function set_read_buffer(data)
	read_buffer = data
	read_pos = 1
	read_bit_accum = 0
	read_bit_pos = 8
end

--- Get the write buffer after writing to get data to send.<br>
--- Flushes any remaining bits in the bit accumulator before returning.<br>
--- Call this after all write operations to get the serialized binary data.<br>
---@return string data The serialized binary data ready to send.
---@usage <br>
--- ```
--- net.writeString("Hello")
--- net.writeInt(42, 32)
--- local data = net.getWriteBuffer()
--- -- Send data over network
--- ```
local function get_write_buffer()
	-- Flush any remaining bits in the accumulator
	if write_bit_pos > 0 then
		write_count = write_count + 1
		write_buffer[write_count] = bit_pack_u8(write_bit_accum)
		write_bit_accum = 0
		write_bit_pos = 0
	end
	return table_concat(write_buffer)
end

-- Helper: ensure buffer has enough bytes for read
local function check_read_length(n)
	if read_pos + n - 1 > #read_buffer then
		return error(
			"Buffer underflow: need " .. n .. " bytes, only " .. (#read_buffer - read_pos + 1) .. " available", 2)
	end
end

-- Helper: append to write buffer
local function append_to_buffer(str)
	-- Flush bit accumulator before appending byte-aligned data
	if write_bit_pos > 0 then
		write_count = write_count + 1
		write_buffer[write_count] = bit_pack_u8(write_bit_accum)
		write_bit_accum = 0
		write_bit_pos = 0
	end
	write_count = write_count + 1
	write_buffer[write_count] = str
end

----------------------------------------------------------------------
-- Byte (8-bit unsigned integer)
----------------------------------------------------------------------

--- Write a single byte (8-bit unsigned integer) to the buffer.<br>
--- Packs the value as an unsigned 8-bit integer.<br>
---@param value number The byte value to write (0-255).
---@usage <br>
--- ```
--- net.writeByte(255)
--- ```
local function net_writeByte(value)
	return append_to_buffer(bit_pack_u8(value))
end

--- Read a single byte (8-bit unsigned integer) from the buffer.<br>
--- Unpacks the value as an unsigned 8-bit integer.<br>
---@return number value The byte value read (0-255).
---@usage <br>
--- ```
--- local b = net.readByte()
--- ```
local function net_readByte()
	check_read_length(1)
	local value = bit_unpack_u8(read_buffer, read_pos)
	read_pos = read_pos + 1
	return value
end

----------------------------------------------------------------------
-- Boolean (single bit)
----------------------------------------------------------------------

--- Write a boolean value as a single bit to the buffer.<br>
--- Uses bit-packing to store booleans efficiently (8 bools per byte).<br>
---@param value boolean The boolean value to write.
---@usage <br>
--- ```
--- net.writeBool(true)
--- net.writeBool(false)
--- ```
local function net_writeBool(value)
	if value then
		write_bit_accum = bit_bor(write_bit_accum, bit_lshift(1, write_bit_pos))
	end
	write_bit_pos = write_bit_pos + 1
	if write_bit_pos == 8 then
		write_count = write_count + 1
		write_buffer[write_count] = bit_pack_u8(write_bit_accum)
		write_bit_accum = 0
		write_bit_pos = 0
	end
end

--- Read a boolean value from a single bit in the buffer.<br>
--- Uses bit-packing to read booleans efficiently (8 bools per byte).<br>
---@return boolean value The boolean value read.
---@usage <br>
--- ```
--- local flag = net.readBool()
--- ```
local function net_readBool()
	if read_bit_pos == 8 then
		check_read_length(1)
		read_bit_accum = bit_unpack_u8(read_buffer, read_pos)
		read_pos = read_pos + 1
		read_bit_pos = 0
	end
	local b = bit_band(bit_rshift(read_bit_accum, read_bit_pos), 1) ~= 0
	read_bit_pos = read_bit_pos + 1
	return b
end

----------------------------------------------------------------------
-- Unsigned integer (8, 16, 32 bits) - little-endian
----------------------------------------------------------------------

--- Write an unsigned integer to the buffer.<br>
--- Supports 8, 16, or 32-bit values in little-endian byte order.<br>
---@param value number The unsigned integer value to write.
---@param num_bits number The bit width (8, 16, or 32).
---@usage <br>
--- ```
--- net.writeUInt(255, 8)   -- 8-bit
--- net.writeUInt(65535, 16) -- 16-bit
--- net.writeUInt(4294967295, 32) -- 32-bit
--- ```
local function net_writeUInt(value, num_bits)
	if num_bits == 8 then
		return append_to_buffer(bit_pack_u8(value))
	end
	if num_bits == 16 then
		return append_to_buffer(bit_pack_u16_le(value))
	end
	if num_bits == 32 then
		return append_to_buffer(bit_pack_le(value))
	end
	return error("Unsupported bit width for UInt: " .. num_bits, 2)
end

--- Read an unsigned integer from the buffer.<br>
--- Supports 8, 16, or 32-bit values in little-endian byte order.<br>
---@param num_bits number The bit width (8, 16, or 32).
---@return number value The unsigned integer value read.
---@usage <br>
--- ```
--- local v8 = net.readUInt(8)
--- local v16 = net.readUInt(16)
--- local v32 = net.readUInt(32)
--- ```
local function net_readUInt(num_bits)
	if num_bits == 8 then
		check_read_length(1)
		local value = bit_unpack_u8(read_buffer, read_pos)
		read_pos = read_pos + 1
		return value
	end
	if num_bits == 16 then
		check_read_length(2)
		local value = bit_unpack_u16_le(read_buffer, read_pos)
		read_pos = read_pos + 2
		return value
	end
	if num_bits == 32 then
		check_read_length(4)
		local value = bit_unpack_le(read_buffer, read_pos)
		read_pos = read_pos + 4
		return value
	end
	return error("Unsupported bit width for UInt: " .. num_bits, 2)
end

----------------------------------------------------------------------
-- Signed integer (8, 16, 32 bits) - little-endian
----------------------------------------------------------------------

--- Write a signed integer to the buffer.<br>
--- Supports 8, 16, or 32-bit values in little-endian byte order.<br>
---@param value number The signed integer value to write.
---@param num_bits number The bit width (8, 16, or 32).
---@usage <br>
--- ```
--- net.writeInt(-128, 8)   -- 8-bit
--- net.writeInt(32767, 16) -- 16-bit
--- net.writeInt(2147483647, 32) -- 32-bit
--- ```
local function net_writeInt(value, num_bits)
	if num_bits == 8 then
		return append_to_buffer(bit_pack_i8(value))
	end
	if num_bits == 16 then
		return append_to_buffer(bit_pack_i16_le(value))
	end
	if num_bits == 32 then
		-- Use tosigned/tounsigned for 32-bit signed
		local unsigned = bit_tounsigned(value)
		return append_to_buffer(bit_pack_le(unsigned))
	end
	return error("Unsupported bit width for Int: " .. num_bits, 2)
end

--- Read a signed integer from the buffer.<br>
--- Supports 8, 16, or 32-bit values in little-endian byte order.<br>
---@param num_bits number The bit width (8, 16, or 32).
---@return number value The signed integer value read.
---@usage <br>
--- ```
--- local v8 = net.readInt(8)
--- local v16 = net.readInt(16)
--- local v32 = net.readInt(32)
--- ```
local function net_readInt(num_bits)
	if num_bits == 8 then
		check_read_length(1)
		local value = bit_unpack_i8(read_buffer, read_pos)
		read_pos = read_pos + 1
		return value
	end
	if num_bits == 16 then
		check_read_length(2)
		local value = bit_unpack_i16_le(read_buffer, read_pos)
		read_pos = read_pos + 2
		return value
	end
	if num_bits == 32 then
		check_read_length(4)
		local unsigned = bit_unpack_le(read_buffer, read_pos)
		read_pos = read_pos + 4
		return bit_tosigned(unsigned)
	end
	return error("Unsupported bit width for Int: " .. num_bits, 2)
end

----------------------------------------------------------------------
-- Float (32-bit IEEE 754) - little-endian
----------------------------------------------------------------------

--- Write a 32-bit IEEE 754 float to the buffer.<br>
--- Converts Lua number (double) to 32-bit float representation.<br>
--- Handles special values: 0, -0, NaN, Infinity, -Infinity.<br>
---@param value number The float value to write.
---@usage <br>
--- ```
--- net.writeFloat(3.14159)
--- net.writeFloat(math.huge)
--- ```
local function net_writeFloat(value)
	-- Convert Lua number (double) to float32 u32 representation
	-- This is a simplified conversion - for full precision, use a proper float32 library
	local m, e = math.frexp(value)
	if value == 0 then
		return append_to_buffer(bit_pack_le(0))
	end
	if value ~= value then -- NaN
		return append_to_buffer(bit_pack_le(0x7FC00000))
	end
	if value == math.huge then
		return append_to_buffer(bit_pack_le(0x7F800000))
	end
	if value == -math.huge then
		return append_to_buffer(bit_pack_le(0xFF800000))
	end

	local sign = 0
	if value < 0 then
		sign = 0x80000000
		m = -m
	end

	-- Convert to float32: 23-bit mantissa, 8-bit exponent (bias 127)
	e = e + 126 -- Adjust for float32 exponent bias
	if e <= 0 then
		-- Subnormal or zero
		m = m * 0.5 ^ (1 - e)
		e = 0
	elseif e >= 255 then
		-- Overflow to infinity
		return append_to_buffer(bit_pack_le(sign + 0x7F800000))
	end

	local mantissa = math.floor((m - 0.5) * 0x1000000 + 0.5)
	local float32 = sign + bit_lshift(e, 23) + (mantissa % 0x800000)
	return append_to_buffer(bit_pack_le(float32))
end

--- Read a 32-bit IEEE 754 float from the buffer.<br>
--- Converts 32-bit float representation back to Lua number (double).<br>
--- Handles special values: 0, -0, NaN, Infinity, -Infinity.<br>
---@return number value The float value read.
---@usage <br>
--- ```
--- local f = net.readFloat()
--- ```
local function net_readFloat()
	check_read_length(4)
	local float32 = bit_unpack_le(read_buffer, read_pos)
	read_pos = read_pos + 4

	-- Convert float32 u32 back to Lua number (double)
	if float32 == 0 then return 0 end
	if float32 == 0x80000000 then return -0 end

	local sign = bit_band(float32, 0x80000000) ~= 0
	local exponent = bit_band(bit_rshift(float32, 23), 0xFF)
	local mantissa = bit_band(float32, 0x7FFFFF)

	if exponent == 0 then
		-- Subnormal
		if mantissa == 0 then return sign and -0 or 0 end
		return (sign and -1 or 1) * mantissa * 2 ^ -149
	end

	if exponent == 255 then
		-- Infinity or NaN
		if mantissa == 0 then return sign and -math.huge or math.huge end
		return 0 / 0 -- NaN
	end

	-- Normalized
	return (sign and -1 or 1) * (1 + mantissa / 0x800000) * 2 ^ (exponent - 127)
end

----------------------------------------------------------------------
-- Double (64-bit IEEE 754) - little-endian
----------------------------------------------------------------------

--- Write a 64-bit IEEE 754 double to the buffer.<br>
--- Uses the bits library for double to uint32 conversion.<br>
---@param value number The double value to write.
---@usage <br>
--- ```
--- net.writeDouble(3.141592653589793)
--- ```
local function net_writeDouble(value)
	local high = bits_double_to_uint32_high(value)
	local low = bits_double_to_uint32_low(value)
	return append_to_buffer(bit_pack_le(high)), append_to_buffer(bit_pack_le(low))
end

--- Read a 64-bit IEEE 754 double from the buffer.<br>
--- Uses the bits library for uint32 to double conversion.<br>
---@return number value The double value read.
---@usage <br>
--- ```
--- local d = net.readDouble()
--- ```
local function net_readDouble()
	check_read_length(8)
	local high = bit_unpack_le(read_buffer, read_pos)
	read_pos = read_pos + 4
	local low = bit_unpack_le(read_buffer, read_pos)
	read_pos = read_pos + 4
	return bits_bin64_to_double(bits_u32_to_bin32(high) .. bits_u32_to_bin32(low))
end

----------------------------------------------------------------------
-- String (length-prefixed with u16)
----------------------------------------------------------------------

--- Write a string to the buffer with a 16-bit length prefix.<br>
--- The string length is written first as a 16-bit unsigned integer,<br>
--- followed by the string content. Supports empty strings.<br>
---@param str string The string to write.
---@usage <br>
--- ```
--- net.writeString("Hello World")
--- net.writeString("") -- empty string
--- ```
local function net_writeString(str)
	local len = #str
	net_writeUInt(len, 16)
	if len > 0 then
		return append_to_buffer(str)
	end
end

--- Read a string from the buffer with a 16-bit length prefix.<br>
--- Reads the 16-bit length first, then reads that many bytes as the string.<br>
---@return string str The string read.
---@usage <br>
--- ```
--- local str = net.readString()
--- ```
local function net_readString()
	local len = net_readUInt(16)
	if len == 0 then
		return ""
	end
	check_read_length(len)
	local str = string_sub(read_buffer, read_pos, read_pos + len - 1)
	read_pos = read_pos + len
	return str
end

----------------------------------------------------------------------
-- Vector (3 floats: x, y, z)
----------------------------------------------------------------------

--- Write a 3D vector to the buffer as three floats.<br>
--- The vector is written as x, y, z float values in sequence.<br>
--- Missing components default to 0.<br>
---@param vec table The vector table with indices 1, 2, 3 for x, y, z.
---@usage <br>
--- ```
--- net.writeVector({100, 200, 300})
--- ```
local function net_writeVector(vec)
	return net_writeFloat(vec[1] or 0), net_writeFloat(vec[2] or 0), net_writeFloat(vec[3] or 0)
end

--- Read a 3D vector from the buffer as three floats.<br>
--- Reads x, y, z float values in sequence and returns them as a table.<br>
---@return table vec The vector table with indices 1, 2, 3 for x, y, z.
---@usage <br>
--- ```
--- local vec = net.readVector()
--- print(vec[1], vec[2], vec[3])
--- ```
local function net_readVector()
	return {
		net_readFloat(),
		net_readFloat(),
		net_readFloat(),
	}
end

local NetWrapper = {
	["boolean"] = {
		read = net_readBool, -- single bit read
		write = net_writeBool, -- single bit write
	},
	["byte"] = {
		read = function() return net_readUInt(8) end,
		write = function(v) return net_writeUInt(v, 8) end, -- tailcall
	},
	["sbyte"] = {
		read = function() return net_readInt(8) end,
		write = function(v) return net_writeInt(v, 8) end, -- tailcall
	},
	["ushort"] = {
		read = function() return net_readUInt(16) end,
		write = function(v) return net_writeUInt(v, 16) end, -- tailcall
	},
	["short"] = {
		read = function() return net_readInt(16) end,
		write = function(v) return net_writeInt(v, 16) end, -- tailcall
	},
	["uint"] = {
		read = function() return net_readUInt(32) end,
		write = function(v) return net_writeUInt(v, 32) end, -- tailcall
	},
	["int"] = {
		read = function() return net_readInt(32) end,
		write = function(v) return net_writeInt(v, 32) end, -- tailcall
	},
	["float"] = {
		read = net_readFloat,
		write = net_writeFloat,
	},
	["double"] = {
		read = net_readDouble,
		write = net_writeDouble,
	},
	["string"] = {
		read = net_readString,
		write = net_writeString,
	},
	["Vector"] = {
		read = net_readVector,
		write = net_writeVector,
	},
}

local function WriteProperty(obj, member, unwrapper)
	local key, kind = member[1], member[2]
	local value = obj[key]
	if isfunction(value) then
		value = value(obj)
	end
	kind.write(unwrapper and unwrapper(value) or value)
end

local function ReadProperty(obj, member, wrapper)
	local key, kind = member[1], member[2]
	local value = kind.read()
	obj[key] = wrapper and wrapper(value) or value
end

-- Module-level scheme methods
local function scheme_write(scheme, unwrapper, obj)
	for i = 1, #scheme do
		WriteProperty(obj, scheme[i], unwrapper)
	end
end

local function scheme_read(scheme, wrapper, obj)
	obj = obj or {}
	for i = 1, #scheme do
		ReadProperty(obj, scheme[i], wrapper)
	end
	return obj
end

-- Export buffer management functions and net_* functions on module
local M = {
	setReadBuffer = set_read_buffer,
	getWriteBuffer = get_write_buffer,
	resetReadBuffer = reset_read_buffer,
	resetWriteBuffer = reset_write_buffer,
	writeByte = net_writeByte,
	readByte = net_readByte,
	writeBool = net_writeBool,
	readBool = net_readBool,
	writeUInt = net_writeUInt,
	readUInt = net_readUInt,
	writeInt = net_writeInt,
	readInt = net_readInt,
	writeFloat = net_writeFloat,
	readFloat = net_readFloat,
	writeDouble = net_writeDouble,
	readDouble = net_readDouble,
	writeString = net_writeString,
	readString = net_readString,
	writeVector = net_writeVector,
	readVector = net_readVector,
}

--- Create a data scheme for structured serialization.<br>
--- Defines a schema with field names and their data types.<br>
--- Fields are sorted alphabetically to ensure consistent ordering between client and server.<br>
--- Supported types: boolean, byte, sbyte, ushort, short, uint, int, float, double, string, Vector.<br>
---@param definition table Field name to type mapping (e.g., {name = "string", health = "int"}).
---@return table scheme The scheme object with read/write methods.
---@usage <br>
--- ```
--- local player_scheme = net.scheme {
---     name = "string",
---     health = "int",
---     position = "Vector",
---     is_admin = "boolean"
--- }
---
--- -- Write using scheme
--- player_scheme:write({ name = "cheatoid", health = 100, position = {0, 0, 0}, is_admin = true })
---
--- -- Read using scheme
--- local data = player_scheme:read()
--- ```
function M.scheme(definition)
	local scheme = {}
	local keys = table.keys(definition)
	table.sort(keys) -- ascending order (must match between client and server)
	for i, key in next, keys do
		local dataType = definition[key]
		assert(isstring(dataType))
		local kind = NetWrapper[dataType]
		assert(istable(kind) and isfunction(kind.read) and isfunction(kind.write))
		local member = { key, kind }
		scheme[i] = member
	end

	scheme.write = scheme_write
	scheme.read = scheme_read

	-- Also expose module functions on scheme for convenience
	for k, v in next, M do
		scheme[k] = v
	end

	return scheme
end

-- Export the API to be accessed by other packages
return M

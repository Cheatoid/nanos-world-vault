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

-- Reset buffers (call before starting a new read/write operation)
local function reset_read_buffer()
	read_buffer = ""
	read_pos = 1
	read_bit_accum = 0
	read_bit_pos = 8
end

local function reset_write_buffer()
	write_buffer = {}
	write_count = 0
	write_bit_accum = 0
	write_bit_pos = 0
end

-- Set read buffer (call with received data before reading)
local function set_read_buffer(data)
	read_buffer = data
	read_pos = 1
	read_bit_accum = 0
	read_bit_pos = 8
end

-- Get write buffer (call after writing to get data to send)
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
local function net_writeByte(value)
	return append_to_buffer(bit_pack_u8(value))
end

local function net_readByte()
	check_read_length(1)
	local value = bit_unpack_u8(read_buffer, read_pos)
	read_pos = read_pos + 1
	return value
end

----------------------------------------------------------------------
-- Boolean (single bit)
----------------------------------------------------------------------
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
local function net_writeDouble(value)
	local high = bits_double_to_uint32_high(value)
	local low = bits_double_to_uint32_low(value)
	return append_to_buffer(bit_pack_le(high)), append_to_buffer(bit_pack_le(low))
end

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
local function net_writeString(str)
	local len = #str
	net_writeUInt(len, 16)
	if len > 0 then
		return append_to_buffer(str)
	end
end

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
local function net_writeVector(vec)
	return net_writeFloat(vec[1] or 0), net_writeFloat(vec[2] or 0), net_writeFloat(vec[3] or 0)
end

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

-- Return factory function for creating schemes
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

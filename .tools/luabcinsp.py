#!/usr/bin/env python3

# Author: Cheatoid ~ https://github.com/Cheatoid
# License: MIT

"""
Lua bytecode inspector for versions 5.1 - 5.4
Usage: python luabcinsp.py <luac_file>
"""

import struct
import sys
from enum import IntEnum


# ----------------------------------------------------------------------
# 1. Basic definitions
# ----------------------------------------------------------------------
class LuaVersion(IntEnum):
    V51 = 0x51
    V52 = 0x52
    V53 = 0x53
    V54 = 0x54


# Instruction format modes
FMT_ABC  = 0  # A, B, C
FMT_ABx  = 1  # A, Bx
FMT_AsBx = 2  # A, sBx (signed Bx)
FMT_Ax   = 3  # Ax (large unsigned)
FMT_ABxC = 4  # special for 5.4 (treated as ABC)

# TODO: Verify OPCODES correctness using official C source code

# ----------------------------------------------------------------------
# 2. Opcode tables for every version
#    Stored as {opcode: (mnemonic, format_mode)}
# ----------------------------------------------------------------------
OPCODES = {
    LuaVersion.V51: {
        0: ("MOVE", FMT_ABC),
        1: ("LOADK", FMT_ABx),
        2: ("LOADBOOL", FMT_ABC),
        3: ("LOADNIL", FMT_ABC),
        4: ("GETUPVAL", FMT_ABC),
        5: ("GETGLOBAL", FMT_ABx),
        6: ("GETTABLE", FMT_ABC),
        7: ("SETGLOBAL", FMT_ABx),
        8: ("SETUPVAL", FMT_ABC),
        9: ("SETTABLE", FMT_ABC),
        10: ("NEWTABLE", FMT_ABC),
        11: ("SELF", FMT_ABC),
        12: ("ADD", FMT_ABC),
        13: ("SUB", FMT_ABC),
        14: ("MUL", FMT_ABC),
        15: ("DIV", FMT_ABC),
        16: ("MOD", FMT_ABC),
        17: ("POW", FMT_ABC),
        18: ("UNM", FMT_ABC),
        19: ("NOT", FMT_ABC),
        20: ("LEN", FMT_ABC),
        21: ("CONCAT", FMT_ABC),
        22: ("JMP", FMT_AsBx),
        23: ("EQ", FMT_ABC),
        24: ("LT", FMT_ABC),
        25: ("LE", FMT_ABC),
        26: ("TEST", FMT_ABC),
        27: ("TESTSET", FMT_ABC),
        28: ("CALL", FMT_ABC),
        29: ("TAILCALL", FMT_ABC),
        30: ("RETURN", FMT_ABC),
        31: ("FORLOOP", FMT_AsBx),
        32: ("FORPREP", FMT_AsBx),
        33: ("TFORLOOP", FMT_ABC),
        34: ("SETLIST", FMT_ABC),
        35: ("CLOSE", FMT_ABC),
        36: ("CLOSURE", FMT_ABx),
        37: ("VARARG", FMT_ABC),
    },
    LuaVersion.V52: {
        0: ("MOVE", FMT_ABC),
        1: ("LOADK", FMT_ABx),
        2: ("LOADKX", FMT_ABx),
        3: ("LOADBOOL", FMT_ABC),
        4: ("LOADNIL", FMT_ABC),
        5: ("GETUPVAL", FMT_ABC),
        6: ("GETTABUP", FMT_ABC),
        7: ("GETTABLE", FMT_ABC),
        8: ("SETTABUP", FMT_ABC),
        9: ("SETUPVAL", FMT_ABC),
        10: ("SETTABLE", FMT_ABC),
        11: ("NEWTABLE", FMT_ABC),
        12: ("SELF", FMT_ABC),
        13: ("ADD", FMT_ABC),
        14: ("SUB", FMT_ABC),
        15: ("MUL", FMT_ABC),
        16: ("DIV", FMT_ABC),
        17: ("MOD", FMT_ABC),
        18: ("POW", FMT_ABC),
        19: ("UNM", FMT_ABC),
        20: ("NOT", FMT_ABC),
        21: ("LEN", FMT_ABC),
        22: ("CONCAT", FMT_ABC),
        23: ("JMP", FMT_AsBx),
        24: ("EQ", FMT_ABC),
        25: ("LT", FMT_ABC),
        26: ("LE", FMT_ABC),
        27: ("TEST", FMT_ABC),
        28: ("TESTSET", FMT_ABC),
        29: ("CALL", FMT_ABC),
        30: ("TAILCALL", FMT_ABC),
        31: ("RETURN", FMT_ABC),
        32: ("FORLOOP", FMT_AsBx),
        33: ("FORPREP", FMT_AsBx),
        34: ("TFORCALL", FMT_ABC),
        35: ("TFORLOOP", FMT_ABC),
        36: ("SETLIST", FMT_ABC),
        37: ("CLOSURE", FMT_ABx),
        38: ("VARARG", FMT_ABC),
        39: ("EXTRAARG", FMT_Ax),
    },
    LuaVersion.V53: {
        0: ("MOVE", FMT_ABC),
        1: ("LOADK", FMT_ABx),
        2: ("LOADKX", FMT_ABx),
        3: ("LOADBOOL", FMT_ABC),
        4: ("LOADNIL", FMT_ABC),
        5: ("GETUPVAL", FMT_ABC),
        6: ("GETTABUP", FMT_ABC),
        7: ("GETTABLE", FMT_ABC),
        8: ("SETTABUP", FMT_ABC),
        9: ("SETUPVAL", FMT_ABC),
        10: ("SETTABLE", FMT_ABC),
        11: ("NEWTABLE", FMT_ABC),
        12: ("SELF", FMT_ABC),
        13: ("ADD", FMT_ABC),
        14: ("SUB", FMT_ABC),
        15: ("MUL", FMT_ABC),
        16: ("MOD", FMT_ABC),
        17: ("POW", FMT_ABC),
        18: ("DIV", FMT_ABC),
        19: ("IDIV", FMT_ABC),
        20: ("BAND", FMT_ABC),
        21: ("BOR", FMT_ABC),
        22: ("BXOR", FMT_ABC),
        23: ("SHL", FMT_ABC),
        24: ("SHR", FMT_ABC),
        25: ("UNM", FMT_ABC),
        26: ("BNOT", FMT_ABC),
        27: ("NOT", FMT_ABC),
        28: ("LEN", FMT_ABC),
        29: ("CONCAT", FMT_ABC),
        30: ("JMP", FMT_AsBx),
        31: ("EQ", FMT_ABC),
        32: ("LT", FMT_ABC),
        33: ("LE", FMT_ABC),
        34: ("TEST", FMT_ABC),
        35: ("TESTSET", FMT_ABC),
        36: ("CALL", FMT_ABC),
        37: ("TAILCALL", FMT_ABC),
        38: ("RETURN", FMT_ABC),
        39: ("FORLOOP", FMT_AsBx),
        40: ("FORPREP", FMT_AsBx),
        41: ("TFORCALL", FMT_ABC),
        42: ("TFORLOOP", FMT_ABC),
        43: ("SETLIST", FMT_ABC),
        44: ("CLOSURE", FMT_ABx),
        45: ("VARARG", FMT_ABC),
        46: ("EXTRAARG", FMT_Ax),
    },
    LuaVersion.V54: {
        0: ("MOVE", FMT_ABC),
        1: ("LOADI", FMT_ABx),
        2: ("LOADF", FMT_ABx),
        3: ("LOADK", FMT_ABx),
        4: ("LOADKX", FMT_ABx),
        5: ("LOADFALSE", FMT_ABC),
        6: ("LFALSESKIP", FMT_ABC),
        7: ("LOADTRUE", FMT_ABC),
        8: ("LOADNIL", FMT_ABC),
        9: ("GETUPVAL", FMT_ABC),
        10: ("SETUPVAL", FMT_ABC),
        11: ("GETTABUP", FMT_ABC),
        12: ("GETTABLE", FMT_ABC),
        13: ("SETTABUP", FMT_ABC),
        14: ("SETTABLE", FMT_ABC),
        15: ("NEWTABLE", FMT_ABC),
        16: ("SELF", FMT_ABC),
        17: ("ADDI", FMT_ABx),
        18: ("ADDK", FMT_ABC),
        19: ("SUBK", FMT_ABC),
        20: ("MULK", FMT_ABC),
        21: ("MODK", FMT_ABC),
        22: ("POWK", FMT_ABC),
        23: ("DIVK", FMT_ABC),
        24: ("IDIVK", FMT_ABC),
        25: ("BANDK", FMT_ABC),
        26: ("BORK", FMT_ABC),
        27: ("BXORK", FMT_ABC),
        28: ("SHRI", FMT_ABx),
        29: ("SHLI", FMT_ABx),
        30: ("ADD", FMT_ABC),
        31: ("SUB", FMT_ABC),
        32: ("MUL", FMT_ABC),
        33: ("MOD", FMT_ABC),
        34: ("POW", FMT_ABC),
        35: ("DIV", FMT_ABC),
        36: ("IDIV", FMT_ABC),
        37: ("BAND", FMT_ABC),
        38: ("BOR", FMT_ABC),
        39: ("BXOR", FMT_ABC),
        40: ("SHL", FMT_ABC),
        41: ("SHR", FMT_ABC),
        42: ("MMBIN", FMT_ABC),
        43: ("MMBINI", FMT_ABC),
        44: ("MMBNK", FMT_ABC),
        45: ("UNM", FMT_ABC),
        46: ("BNOT", FMT_ABC),
        47: ("NOT", FMT_ABC),
        48: ("LEN", FMT_ABC),
        49: ("CONCAT", FMT_ABC),
        50: ("CLOSE", FMT_ABC),
        51: ("TBC", FMT_ABC),
        52: ("JMP", FMT_AsBx),
        53: ("EQ", FMT_ABC),
        54: ("LT", FMT_ABC),
        55: ("LE", FMT_ABC),
        56: ("EQK", FMT_ABC),
        57: ("EQI", FMT_ABx),
        58: ("LTI", FMT_ABx),
        59: ("LEI", FMT_ABx),
        60: ("GTI", FMT_ABx),
        61: ("GEI", FMT_ABx),
        62: ("TEST", FMT_ABC),
        63: ("TESTSET", FMT_ABC),
        64: ("CALL", FMT_ABC),
        65: ("TAILCALL", FMT_ABC),
        66: ("RETURN", FMT_ABC),
        67: ("RETURN0", FMT_ABC),
        68: ("RETURN1", FMT_ABC),
        69: ("FORLOOP", FMT_AsBx),
        70: ("FORPREP", FMT_AsBx),
        71: ("TFORPREP", FMT_ABC),
        72: ("TFORCALL", FMT_ABC),
        73: ("TFORLOOP", FMT_ABC),
        74: ("SETLIST", FMT_ABC),
        75: ("CLOSURE", FMT_ABx),
        76: ("VARARG", FMT_ABC),
        77: ("VARARGPREP", FMT_ABC),
        78: ("EXTRAARG", FMT_Ax),
    },
}


# ----------------------------------------------------------------------
# 3. Bytecode reader
# ----------------------------------------------------------------------
class LuaBytecode:
    def __init__(self, data: bytes):
        self.data = data
        self.pos = 0
        self.version = None
        self.sizes = {}
        self.endian = "<"  # assume little-endian

    # -------- low-level reading helpers --------
    def read_bytes(self, n):
        res = self.data[self.pos : self.pos + n]
        self.pos += n
        return res

    def read_byte(self):
        return self.read_bytes(1)[0]

    def read_uint(self, size):
        fmt = self.endian + {1: "B", 2: "H", 4: "I", 8: "Q"}[size]
        return struct.unpack(fmt, self.read_bytes(size))[0]

    def read_int(self, size):
        fmt = self.endian + {1: "b", 2: "h", 4: "i", 8: "q"}[size]
        return struct.unpack(fmt, self.read_bytes(size))[0]

    def read_size_t(self):
        return self.read_uint(self.sizes["size_t"])

    def read_instruction(self):
        return self.read_uint(self.sizes["Instruction"])

    def read_lua_number(self):
        size = self.sizes["lua_Number"]
        fmt = self.endian + {4: "f", 8: "d"}[size]
        return struct.unpack(fmt, self.read_bytes(size))[0]

    def read_lua_integer(self):
        if "lua_Integer" in self.sizes:
            size = self.sizes["lua_Integer"]
            return self.read_int(size)
        return None  # 5.1 doesn't have this

    def read_string(self):
        size = self.read_size_t()
        if size == 0:
            return ""
        # size can be huge if stripped debug? safeguard
        raw = self.read_bytes(size)
        # strip trailing zero if present (C string)
        if raw[-1] == 0:
            raw = raw[:-1]
        return raw.decode("utf-8", errors="replace")

    # -------- header --------
    def parse_header(self):
        sig = self.read_bytes(4)
        if sig != b"\x1bLua":
            raise ValueError("Not a Lua bytecode file")
        self.version = LuaVersion(self.read_byte())
        fmt_byte = self.read_byte()
        if fmt_byte != 0:
            raise ValueError(f"Unsupported format version: {fmt_byte}")

        if self.version == LuaVersion.V51:
            # endianness flag
            endian = self.read_byte()
            if endian == 1:
                self.endian = "<"
            else:
                self.endian = ">"
            self.sizes["int"] = self.read_byte()
            self.sizes["size_t"] = self.read_byte()
            self.sizes["Instruction"] = self.read_byte()
            self.sizes["lua_Number"] = self.read_byte()
        else:
            # 5.2/5.3/5.4: no endian byte, assume LE (most hosts)
            self.sizes["int"] = self.read_byte()
            self.sizes["size_t"] = self.read_byte()
            self.sizes["Instruction"] = self.read_byte()
            self.sizes["lua_Integer"] = self.read_byte()
            self.sizes["lua_Number"] = self.read_byte()

    # -------- constants --------
    def read_constant(self):
        """Read one constant and return a Lua object (number, string, bool, nil)."""
        tag = self.read_byte()
        if self.version == LuaVersion.V51:
            if tag == 3:  # LUA_TNUMBER
                return self.read_lua_number()
            elif tag == 4:  # LUA_TSTRING
                return self.read_string()
            else:
                raise ValueError(f"Unknown constant tag in 5.1: {tag}")
        elif self.version in (LuaVersion.V52, LuaVersion.V53):
            if tag == 0:  # LUA_TNIL
                return None
            elif tag == 1:  # LUA_TBOOLEAN
                return bool(self.read_byte())
            elif tag == 3 or tag == (3 | 16):  # LUA_TNUMBER / LUA_TNUMINT
                # In 5.2 only tag 3 exists, 5.3 uses tag 3 for float, 19 for int
                if tag == (3 | 16) or self.version == LuaVersion.V53:
                    return self.read_lua_integer()
                else:
                    return self.read_lua_number()
            elif tag == 4:  # LUA_TSTRING
                return self.read_string()
            else:
                raise ValueError(f"Unknown constant tag in 5.2/5.3: {tag}")
        elif self.version == LuaVersion.V54:
            # 5.4 constant tags: 0 nil, 1 false, 17 true, 3 float, 19 integer, 4 string
            if tag == 0:
                return None
            elif tag == 1:
                return False
            elif tag == 17:
                return True
            elif tag == 3:  # float
                return self.read_lua_number()
            elif tag == 19:  # integer
                return self.read_lua_integer()
            elif tag == 4:
                return self.read_string()
            else:
                raise ValueError(f"Unknown constant tag in 5.4: {tag}")

    # -------- instruction decoding --------
    def decode_instruction(self, insn):
        """Return (mnemonic, A, B, C, Bx, sBx, Ax) according to opcode mode."""
        assert (
            self.version is not None
        ), "Header must be parsed before decoding instructions"
        if self.version == LuaVersion.V54:
            op = insn & 0x7F
            # extract fields depending on opcode mode
            table = OPCODES[self.version]
            if op not in table:
                raise ValueError(f"Unknown 5.4 opcode {op}")
            name, mode = table[op]
            A = (insn >> 7) & 0xFF
            if mode == FMT_ABC:
                B = (insn >> 24) & 0xFF
                C = (insn >> 15) & 0x1FF
                Bx = (B << 9) | C
                sBx = Bx - 0x10000 if Bx >= 0x8000 else Bx
                Ax = 0
            elif mode == FMT_ABx:
                Bx = (insn >> 15) & 0x1FFFF
                sBx = Bx - 0x10000 if Bx >= 0x8000 else Bx
                B = (Bx >> 9) & 0xFF
                C = Bx & 0x1FF
                Ax = 0
            elif mode == FMT_AsBx:
                sBx = (insn >> 15) & 0x1FFFF
                sBx = sBx - 0x20000 if sBx >= 0x10000 else sBx
                Bx = sBx + 0x10000 if sBx < 0 else sBx
                B = (Bx >> 9) & 0xFF
                C = Bx & 0x1FF
                Ax = 0
            elif mode == FMT_Ax:
                Ax = (insn >> 7) & 0x1FFFFFF
                B = C = Bx = sBx = 0
            else:
                raise ValueError("Unknown format mode")
            return name, A, B, C, Bx, sBx, Ax
        else:
            # 5.1-5.3: 32-bit, opcode in lowest 6 bits
            op = insn & 0x3F
            table = OPCODES[self.version]
            if op not in table:
                raise ValueError(f"Unknown opcode {op}")
            name, mode = table[op]
            A = (insn >> 6) & 0xFF
            if mode == FMT_ABC:
                C = (insn >> 14) & 0x1FF
                B = (insn >> 23) & 0x1FF
                Bx = (B << 9) | C
                sBx = (
                    Bx - 131071
                )  # 0x1FFFF >> 1 ~ 131071? Actually 2^17=131072, offset = 131071
                if Bx >= 0x20000:
                    raise ValueError("Bx too large")
                sBx = Bx - 131071
            elif mode == FMT_ABx:
                Bx = (insn >> 14) & 0x3FFFF
                sBx = Bx - 131071
                B = (Bx >> 9) & 0x1FF
                C = Bx & 0x1FF
            elif mode == FMT_AsBx:
                sBx = (insn >> 14) & 0x3FFFF
                sBx = sBx - 131071
                Bx = sBx + 131071
                B = (Bx >> 9) & 0x1FF
                C = Bx & 0x1FF
            elif mode == FMT_Ax:
                Ax = (insn >> 6) & 0x3FFFFFF
                B = C = Bx = sBx = 0
            else:
                raise ValueError("Unknown format mode")
            return name, A, B, C, Bx, sBx, Ax

    # -------- function prototype --------
    def parse_function(self, depth=0):
        """Parse one function prototype and return a dict with all info."""
        assert self.version is not None
        proto = {}
        proto["depth"] = depth
        proto["source"] = self.read_string()
        proto["line_defined"] = self.read_int(self.sizes["int"])
        proto["last_line_defined"] = self.read_int(self.sizes["int"])
        proto["num_upvalues"] = self.read_byte()
        proto["num_params"] = self.read_byte()
        proto["is_vararg"] = self.read_byte()
        proto["max_stack_size"] = self.read_byte()

        # code
        code_len = self.read_size_t()
        code = []
        for _ in range(code_len):
            code.append(self.read_instruction())
        proto["code"] = code

        # constants
        const_len = self.read_size_t()
        constants = []
        for _ in range(const_len):
            constants.append(self.read_constant())
        proto["constants"] = constants

        # upvalues
        upval_len = self.read_size_t()
        upvalues = []
        for _ in range(upval_len):
            if self.version <= LuaVersion.V53:
                upvalues.append(
                    {
                        "instack": self.read_byte(),
                        "idx": self.read_byte(),
                    }
                )
            else:  # 5.4
                upvalues.append(
                    {
                        "name": self.read_string(),
                        "instack": self.read_byte(),
                        "idx": self.read_byte(),
                    }
                )
        proto["upvalues"] = upvalues

        # sub-protos
        sub_len = self.read_size_t()
        sub_protos = []
        for _ in range(sub_len):
            sub_protos.append(self.parse_function(depth + 1))
        proto["sub_protos"] = sub_protos

        # debug info
        line_info_len = self.read_size_t()
        proto["line_info"] = [
            self.read_int(self.sizes["int"]) for _ in range(line_info_len)
        ]
        local_len = self.read_size_t()
        locals = []
        for _ in range(local_len):
            loc = {
                "name": self.read_string(),
                "startpc": self.read_int(self.sizes["int"]),
                "endpc": self.read_int(self.sizes["int"]),
            }
            locals.append(loc)
        proto["locals"] = locals

        upval_name_len = self.read_size_t()
        upval_names = [self.read_string() for _ in range(upval_name_len)]
        proto["upvalue_names"] = upval_names
        return proto

    # -------- expression stack simulation --------
    def simulate_stack(self, code, constants):
        """Build a list of symbolic expressions for each register."""
        stack: list[str | None] = [None] * 256  # enough for max_stack_size
        result = []
        for i, insn in enumerate(code):
            name, A, B, C, Bx, sBx, Ax = self.decode_instruction(insn)
            comment = ""

            # helper to get value of RK: if B > 0xFF then constant index = B & 0xFF
            def RK(x):
                return f"R{x}" if x < 0x100 else f"K[{x & 0xFF}]"

            def S(x):
                return str(constants[x]) if 0 <= x < len(constants) else f"K[{x}]"

            if name == "MOVE":
                comment = f"R{A} := R{B}"
                stack[A] = stack[B]
            elif name == "LOADK":
                comment = f"R{A} := {S(Bx)}"
                stack[A] = S(Bx)
            elif name == "LOADKX":
                # next instruction is EXTRAARG
                if i + 1 < len(code):
                    _, _, _, _, _, _, Ax = self.decode_instruction(code[i + 1])
                    idx = Ax
                    comment = f"R{A} := {S(idx)}"
                    stack[A] = S(idx)
            elif name == "LOADBOOL":
                comment = f"R{A} := {bool(B)}; if C skip next"
                stack[A] = str(bool(B))
            elif name == "LOADNIL":
                comment = f"R{A}..R{A+B} := nil"
                for r in range(A, A + B + 1):
                    stack[r] = "nil"
            elif name == "GETUPVAL":
                comment = f"R{A} := upval[{B}]"
                stack[A] = f"upval[{B}]"
            elif name == "GETGLOBAL":
                comment = f"R{A} := _ENV[{S(Bx)}]"
                stack[A] = f"_ENV[{S(Bx)}]"
            elif name == "GETTABLE":
                comment = f"R{A} := R{B}[{RK(C)}]"
                stack[A] = f"{stack[B]}[{RK(C)}]"
            elif name == "SETGLOBAL":
                comment = f"_ENV[{S(Bx)}] := R{A}"
            elif name == "SETTABLE":
                comment = f"R{A}[{RK(B)}] := {RK(C)}"
            elif name == "NEWTABLE":
                comment = f"R{A} := {{}} (array={B}, hash={C})"
                stack[A] = "{}"
            elif name == "SELF":
                comment = f"R{A+1} := R{B}; R{A} := R{B}[{RK(C)}]"
            elif name in (
                "ADD",
                "SUB",
                "MUL",
                "DIV",
                "POW",
                "MOD",
                "IDIV",
                "BAND",
                "BOR",
                "BXOR",
                "SHL",
                "SHR",
                "ADDI",
                "ADDK",
                "SUBK",
                "MULK",
                "MODK",
                "POWK",
                "DIVK",
                "IDIVK",
                "BANDK",
                "BORK",
                "BXORK",
                "SHRI",
                "SHLI",
            ):
                opmap = {
                    "ADD": "+",
                    "SUB": "-",
                    "MUL": "*",
                    "DIV": "/",
                    "POW": "^",
                    "MOD": "%",
                    "IDIV": "//",
                    "BAND": "&",
                    "BOR": "|",
                    "BXOR": "~",
                    "SHL": "<<",
                    "SHR": ">>",
                    "ADDI": "+",
                    "ADDK": "+",
                    "SUBK": "-",
                    "MULK": "*",
                    "MODK": "%",
                    "POWK": "^",
                    "DIVK": "/",
                    "IDIVK": "//",
                    "BANDK": "&",
                    "BORK": "|",
                    "BXORK": "~",
                    "SHRI": ">>",
                    "SHLI": "<<",
                }
                sym = opmap.get(name, name)
                op1 = RK(B) if name in ("ADDI", "SHRI", "SHLI") else stack[B]
                op2 = S(sBx) if name in ("ADDI", "SHRI", "SHLI") else RK(C)
                comment = f"R{A} := {op1} {sym} {op2}"
                stack[A] = f"({op1} {sym} {op2})"
            elif name == "UNM":
                comment = f"R{A} := -R{B}"
                stack[A] = f"(-{stack[B]})"
            elif name == "NOT":
                comment = f"R{A} := not R{B}"
                stack[A] = f"(not {stack[B]})"
            elif name == "LEN":
                comment = f"R{A} := #R{B}"
                stack[A] = f"#{stack[B]}"
            elif name == "CONCAT":
                comment = f"R{A} := R{B} .. ... .. R{C}"
                stack[A] = f"concat({B},{C})"
            elif name == "JMP":
                target = i + 1 + sBx
                comment = f"goto {target}"
            elif name == "EQ":
                comment = f"if ({RK(B)} == {RK(C)}) then PC++ else skip"
            elif name == "LT":
                comment = f"if ({RK(B)} < {RK(C)}) then PC++ else skip"
            elif name == "LE":
                comment = f"if ({RK(B)} <= {RK(C)}) then PC++ else skip"
            elif name == "TEST":
                comment = f"if not R{A} then PC++"
            elif name == "TESTSET":
                comment = f"if R{B} then R{A} := R{B} else PC++"
            elif name == "CALL":
                comment = f"R{A} := R{A}( ... ) {"(tail)" if False else ""}"
                stack[A] = f"<call>"
            elif name == "RETURN":
                comment = f"return R{A}..R{A+B-1}"
            elif name == "FORLOOP":
                comment = f"R{A} += R{A+2}; if R{A} <= R{A+1} then PC+=sBx"
            elif name == "FORPREP":
                comment = f"R{A} -= R{A+2}; PC+=sBx"
            elif name == "SETLIST":
                comment = f"R{A}[(C-1)*FPF+i] := R{A+i}"
            elif name == "CLOSURE":
                comment = f"R{A} := closure(K[{Bx}])"
                stack[A] = f"<closure {Bx}>"
            elif name == "VARARG":
                comment = f"R{A}..R{A+B-1} := ..."
            # generic fallback
            result.append((i, f"{name:12s} {A:3d} {B:3d} {C:3d}", comment))
        return result


# ----------------------------------------------------------------------
# 4. Display logic
# ----------------------------------------------------------------------
def show_proto(proto, version, indent=0):
    prefix = "  " * indent
    print(
        f"{prefix}function <{proto['source']}:{proto['line_defined']}> "
        f"({proto['num_params']} params, {proto['max_stack_size']} slots, "
        f"{len(proto['code'])} opcodes)"
    )
    # constants
    if proto["constants"]:
        print(f"{prefix}  constants:")
        for i, k in enumerate(proto["constants"]):
            print(f"{prefix}    [{i}] {repr(k)}")
    # upvalues
    if proto["upvalues"]:
        print(f"{prefix}  upvalues:")
        for i, uv in enumerate(proto["upvalues"]):
            desc = "stack" if uv["instack"] else "outer"
            print(f"{prefix}    [{i}] {desc} idx={uv['idx']}", end="")
            if version <= LuaVersion.V53 and i < len(proto.get("upvalue_names", [])):
                print(f" name='{proto['upvalue_names'][i]}'", end="")
            elif version == LuaVersion.V54:
                print(f" name='{uv.get('name','')}'", end="")
            print()
    # code disassembly with expression simulation
    if proto["code"]:
        bytecode = LuaBytecode(b"")  # dummy, only to call decode
        bytecode.version = version
        bytecode.sizes = {}  # not needed for decode
        sim = bytecode.simulate_stack(proto["code"], proto["constants"])
        print(f"{prefix}  code:")
        for i, (inst_text, comment) in sim:
            print(f"{prefix}    {i:4d}  {inst_text:30s} ; {comment}")
    # locals
    if proto["locals"]:
        print(f"{prefix}  locals:")
        for loc in proto["locals"]:
            print(f"{prefix}    {loc['name']}  pc {loc['startpc']}-{loc['endpc']}")
    # sub-protos
    for kid in proto["sub_protos"]:
        show_proto(kid, version, indent + 1)


def main():
    if len(sys.argv) < 2:
        print("Usage: python luabcinsp.py <file>")
        sys.exit(1)
    with open(sys.argv[1], "rb") as f:
        data = f.read()
    bc = LuaBytecode(data)
    bc.parse_header()
    assert bc.version is not None
    print(f"Lua {bc.version.name} (format {bc.endian} endian, sizes: {bc.sizes})")
    main_proto = bc.parse_function()
    show_proto(main_proto, bc.version)


if __name__ == "__main__":
    main()

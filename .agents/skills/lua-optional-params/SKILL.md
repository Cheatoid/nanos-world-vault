---
name: lua-optional-params
description: Find Lua function parameters that accept nil or have a default value but are missing the optional marker in their LuaDoc annotation. Use when auditing LuaDoc correctness, fixing optional parameter annotations, or when the user mentions default params, missing question marks, or optional arguments. Applies to Lua files with ---@param annotations.
---

# Lua Optional Params

Find and fix Lua function parameters that behave as optional in code but are annotated as required in LuaDoc (missing `?` after the parameter name).

Complements `lua-docs-style`: that skill covers overall doc shape, this one covers only the required-vs-optional correctness of `@param` lines.

## Trigger phrases

- find default params / unmarked optional params
- missing question mark on params
- which params should be optional
- audit param annotations for defaults
- fix optional annotations like Memory.dump

## Correctness rule

In this codebase (LuaLS style), an optional parameter is written with `?` after the **name**, before the type:

```lua
---@param start? number Starting address (default: 0)
---@param length? number Number of bytes to dump (default: 64)
```

A parameter is optional if a caller may omit it or pass `nil` and the function still works — typically because the body substitutes a default or takes an early nil-tolerant path. If either holds, the `@param` name **must** end with `?`, regardless of the description text.

Do not confuse with nullable type (`number?`, `string?`): that marks the *type* as nullable. An omittable parameter needs `name?`. A parameter can need both (`---@param value? number? ...`), but the missing-`?`-on-name case is what this skill hunts.

## Motivating example (do not regress)

`library/Shared/@cheatoid/vm/vm.lua`, before (wrong):

```lua
---@param self Memory The memory instance
---@param start number Starting address (default: 0)
---@param length number Number of bytes to dump (default: 64)
---@return string dump Hex dump string
function Memory.dump(self, start, length)
	start = start or 0
	length = length or 64
```

After (correct — only the two `?` markers change):

```lua
---@param self Memory The memory instance
---@param start? number Starting address (default: 0)
---@param length? number Number of bytes to dump (default: 64)
---@return string dump Hex dump string
function Memory.dump(self, start, length)
	start = start or 0
	length = length or 64
```

Any description containing `(default: ...)` or `(optional)` / leading `Optional ...` without a `?` on the name is an automatic flag.

## Evidence signals (body wins over prose)

For each `function Name(a, b, c)` collect its directly-attached `---@param` block, then inspect roughly the first 10–15 lines of the body for the parameter. Strongest first:

1. **Or-default assignment:** `param = param or <default>` (e.g. `start = start or 0`, `maxLength = maxLength or 4096`, `width = width or 4`, `value = value or 0`, `startAddress = startAddress or 0`). Flag if annotation lacks `?`.
2. **Nil-to-default assignment:** `if param == nil then param = <default> end` (e.g. `Utils.toDWords`: `if value == nil then value = 0 end`; `Registers.updateFlags`: `if result == nil then result = 0 end`). Flag.
3. **Nil-tolerant early return:** `if param == nil then return <fallback> end` (e.g. `Utils.toHex`: `if num == nil then return "nil" end`; `Utils.split`: `if str == nil then return {} end`; `Utils.trim`: `if str == nil then return "" end`; `Memory.readByte`: `if address == nil then return 0 end`; `Registers.get`: `if index == nil then return 0 end`; `VM.intToFloat`: `if i == nil then return 0.0 end`). Flag — the function explicitly accepts nil.
4. **Nil guard in a multi-condition:** `if param == nil or ... then return ... end` (e.g. `Memory.writeByte`: `if address == nil or value == nil then return end`; `Memory.allocate`: `if size == nil or size <= 0 then return 0 end`). Flag each nil-tested parameter.
5. **Inline or-default use (no assignment):** `(param or <default>)`, `tonumber(param) or <default>` (e.g. `Utils.fromDWords`: `(b0 or 0) + ((b1 or 0) * ...)`; opcode handlers: `(v or 0)`; `self.data[address] or 0`; `self.r[index] or 0`). Flag if the parameter has no other required use. Note `b0` in `fromDWords` is correctly unannotated/optional-behaving — if it gains an annotation it must be `b0?`.
6. **Doc-text admission:** description contains `(default: ...)`, backtick-default ``(default: `...`)``, `(optional)`, leading `Optional ...`, or `or nil ...` (e.g. `Utils.parseRegister` return `or nil if invalid` pattern generalized). If the name lacks `?`, flag even when the body was not matched — but prefer confirming with signals 1–5.

## Do NOT flag

- Truly required parameters: body indexes/calls them unconditionally with no nil check, or raises on nil (`error(...)`, `assert(param)`, `error("Cannot open file: " .. filename)` as in `VM.loadFile`'s `filename`).
- Loop-boundary or computed-value `or` that is not about the parameter itself (e.g. `self.r[i] or 0` is about a table slot, not a parameter).
- `self` handling: follow the file's existing convention. If the file documents `self` (like `vm.lua` `Memory`/`Registers`/`VM` methods do per `lua-docs-style`), keep the line and only fix `?` if `self` itself had default evidence (it never should). If the file omits `self`, do not add it.
- Anonymous opcode/dispatcher callbacks (`function(vm, d, s)`, `function(vm, a)`) with no `---@param` block: out of scope unless asked to document them.

## Workflow

1. Read the target Lua file fully (and `lua-docs-style/SKILL.md` reference if doc shape is also in question).
2. For each function with a `---@param` block, build a table: signature order, annotation name (strip trailing `?`), annotation type, body evidence (quote the exact matching line).
3. Mark every annotated parameter where body signals 1–5 or doc signal 6 apply but the annotation name has no `?`.
4. Secondary check: an optional parameter positioned before a required one (Lua callers cannot skip it) — report separately, do not reorder code.
5. Fix: add `?` immediately after the parameter name only (`---@param start number` → `---@param start? number`). Never move the `?` onto the type, never change types, defaults, descriptions, or code. If the description lacks any `(default: X)` / `(optional)` hint and evidence is from the body, leave the description untouched unless the user asked for prose updates.
6. Verify: every `---@param` whose description mentions default/optional now has `name?`; every `param = param or ...` / `if param == nil ...` in the scanned scope has a matching `name?`; no `type?`-only line was mistaken for an optional marker; no code lines changed.

## Report format

List findings as: `function Name (line N): param 'x' — evidence "exact code line / doc phrase" — fix: @param x → @param x?`. Group clean functions silently.

Example findings from `vm.lua` this skill must reproduce:

- `Utils.toHex (line 79): num — evidence 'if num == nil then return "nil" end' + doc '(default: 0)' — fix: @param num → @param num?` (`width` already `width?`, correct.)
- `Utils.toDWords (line 92): value — evidence 'if value == nil then value = 0 end' + doc '(default: 0)' — fix: @param value → @param value?`
- `Utils.split (line 116): str, delimiter — evidence 'if str == nil then return {} end' + 'delimiter = delimiter or "\\n"' — fix both to str?/delimiter?`
- `Memory.writeWord/writeDWord: value — evidence 'value = value or 0' — fix to value?`
- `Memory.readString: address — evidence 'if address == nil then return "" end' — fix to address?` (`maxLength?` already correct.)
- `Memory.dump (line 328): start, length — evidence 'start = start or 0' / 'length = length or 64' — fix both to start?/length?`
- `Registers.get/set, isFlagSet/setFlag, updateFlags result, VM.intToFloat i, VM.floatToInt f, VM.loadFile startAddress` — same pattern, each nil-tested or or-defaulted param gets `?`.

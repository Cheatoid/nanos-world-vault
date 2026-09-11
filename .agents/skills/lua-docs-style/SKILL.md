---
name: lua-docs-style
description: Document Lua files with LuaDoc/LuaLS annotations following this codebase's established style. Use when the user asks to document a Lua file, add LuaDoc comments, annotate functions/classes, or add documentation like timer.lua, xml.lua or svg.lua. Applies to Lua files.
---

# Lua Docs Style

Add LuaDoc (LuaLS) annotations to Lua files in this repository without changing any code logic. Match the existing style exactly.

## Trigger phrases

- document this Lua file
- add LuaDoc/LuaDocs documentation
- add annotations like xml.lua or like svg.lua
- describe the API

## Reference files

Read one of these before starting, depending on target shape:

- library/Shared/@cheatoid/standalone/xml.lua - module table with public functions
- library/Shared/@cheatoid/standalone/svg.lua - same, with internal parser helpers
- library/Shared/@cheatoid/collections/Deque.lua - class-based style with class, field, usage
- library/Shared/@cheatoid/timer/timer.lua - type aliases, TimerOptions named options class with optional fields
- library/Shared/@cheatoid/standard/string.d.lua - meta file with class declaration, function stubs, camelCase and PascalCase alias assignments, named options classes, usage examples

## Documentation rules

### Annotation syntax

Every annotation line starts with exactly three dashes followed by @tag. Use these tags in this codebase (do not invent new ones):

- Plain description line - a line starting with three dashes and no @tag, placed before the param and return lines. Use the HTML break tag br for hard line breaks in multi-sentence descriptions.
- @param name type description - parameter. Local variable name first, then the type, then a short description that usually begins with a noun matching the name (for example source, position, message).
- @return type name description - return value. Type first, then a return value name, then a short description. One line per return value.
- @class Name - class declaration (the first @class line carries the description above it).
- @field name type description - class field, either a named field (for example "major integer The major version number.") or an array slot using the [index] form (for example "[1] table Container table storing the deque items.").
- @usage followed by a fenced code block - usage example. Use exactly one `@usage` line per doc block (`---@usage <br>`), then a plain `---` fenced code block. Do NOT repeat `@usage` on fence or code lines:
---@usage <br>
--- ```
--- local deque = Deque.new()
--- deque:pushBack(1)
--- ```
- @overload fun(...) - overload signature.

### Type notation

- Nullable types use a question mark suffix: string?, table?, integer? - never the pipe-nil form.
- Table/list types are just table with a description of the element shape.
- Use integer (not number) for indices, counts, byte values, and depths.
- Use function for callbacks, boolean for flags.

### Formatting

- One @param line per parameter, in declaration order.
- Multiple returns: one @return line each, in return order.
- First line of a doc block is a plain description line, not a tag.
- Keep descriptions short (3-8 words); put details in preceding plain lines.
- Indent with tabs inside function bodies; doc comments align with the function.
- Doc block sits directly above the function or class, no blank line between.
- `@usage` appears at most once per doc block. Fence and code lines use plain `---`, never `---@usage`.
- Do not translate the existing comment lines inside the body; leave code unchanged.

### Documenting options-table arguments

There are two accepted styles. Pick the one that matches the surrounding file.

#### Style A: inline bullets

When the options table has no standalone class and is documented at the call site, use a @param line ending with a colon followed by indented bullet lines.

---@param opts? table Optional configuration options:
--- - model (MovementModel, default: `MovementModel()`): Movement model for validation
--- - sampleCapacity (number, default: 60): Maximum number of snapshots to keep in history

Reference example: library/Shared/@cheatoid/anticheat/anticheat.lua PlayerTrack:init.

Each bullet uses backticks around the option name, lists the type and default in parentheses, and ends with a colon followed by a short description.

#### Style B: named options class

When the options table is reused or belongs to a typed extension, define a @class named after the receiver plus the Options suffix, then reference it from @param.

---@class string.TruncateOptions
---@field ellipsis? string Ellipsis character to use (default: "...").

---@param opts? string.TruncateOptions Options table.

Reference example: library/Shared/@cheatoid/standard/string.d.lua string.truncate and string.truncate_middle.

Naming rule: ReceiverTypeName.Options (for example string.TruncateOptions, not TruncateOptions alone).

### What to document

- Every public function on the returned module table.
- Every local helper function (parse_, process_, find_) when in parser or serializer files.
- Class tables and their metatable methods (len, pairs, new).
- Skip trivial one-liners only when they are obvious; when unsure, document.

### What not to do

- Never change code, only add or prefix comments.
- Do not add a header block unless the file already has one.
- Do not add a param for implicit self unless the file already does (see Deque.lua - it does document self).
- Do not add module, see, diagnostic, generic, or meta tags unless the target file already uses them.

## Workflow

1. Read the target Lua file fully.
2. Read one matching reference file from the list above.
3. Add doc blocks above every function (and class, if present) following the exact style.
4. Verify: no code lines changed, all tags are lowercase, nullable uses the question mark suffix, no pipe-nil remains, only one `@usage` per block with plain `---` fences.
5. Report what was documented and which reference file was used.

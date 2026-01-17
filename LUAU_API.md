# Luaz Zig Luau API Guide

This guide focuses on the high-level `luaz.Lua` API so you can be productive quickly, while pointing you to
the right files for deeper or low-level work.

## Quick start

```zig
const std = @import("std");
const luaz = @import("luaz");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var lua = try luaz.Lua.init(&allocator); // or Lua.init(null)
    defer lua.deinit();

    lua.openLibs();

    const result = try lua.eval("return 2 + 3", .{}, i32);
    std.debug.print("2 + 3 = {}\n", .{result.ok.?});

    const globals = lua.globals();
    try globals.set("message", "Hello from Zig");
    const message = try globals.get("message", []const u8);
    std.debug.print("{s}\n", .{message});
}
```

## Core concepts and lifetimes

- `luaz.Lua` is the main handle to a Luau VM. Call `openLibs()` once after init.
- Reference types must be released with `deinit()` to avoid leaks:
  - `Lua.Table`, `Lua.Function`, `Lua.Buffer`, `Lua.Ref`, and `Lua.Value` (if it holds references).
  - The globals table from `lua.globals()` is a special case and does not need `deinit()`.
- `Lua.Result(T)` is returned by `eval`, `exec`, and function calls:
  - `.ok` and `.yield` contain `?T`; `.debugBreak` indicates a debugger interrupt.
- Errors are raised as Zig errors (`Lua.Error`), not Lua values.
- String slices (`[]const u8`) are borrowed from Lua. Keep them only while the Lua value they came from
  is still referenced; copy if you need to store long-term without keeping a Lua reference.

## Executing code

### Compile and run (convenience)

```zig
const result = try lua.eval("return math.sqrt(16)", .{}, f64);
std.debug.print("sqrt = {d}\n", .{result.ok.?});
```

`eval()` compiles and executes in one step. For production, prefer offline compilation.

### Compile offline and execute bytecode

```zig
const compile_result = try luaz.Compiler.compile("return 6 * 7", .{});
defer compile_result.deinit();

switch (compile_result) {
    .ok => |bytecode| {
        const result = try lua.exec(bytecode, i32);
        std.debug.print("result = {}\n", .{result.ok.?});
    },
    .err => |message| {
        std.debug.print("compile error: {s}\n", .{message});
    },
}
```

`Compiler.Result.deinit()` is required to free the returned buffer.

## Type conversion basics

`luaz` converts values between Zig and Lua automatically:

- Numbers: Zig integers and floats map to Lua numbers.
- Booleans: `bool` maps to Lua `true`/`false`.
- Strings: `[]const u8`, `[:0]const u8` map to Lua strings.
- Optionals: `?T` maps to Lua `nil` and back.
- Tuples: `struct { T1, T2, ... }` maps to multiple return values.
- Arrays: `[N]T` maps to Lua arrays (1-based indexing).
- Vectors: `@Vector(State.VECTOR_SIZE, f32)` maps to Luau native vectors.
- Dynamic values: `Lua.Value` holds any Lua type at runtime.
- Persistent references: `Lua.Ref` holds a registry reference across calls.
- Varargs: `Lua.Varargs` lets Zig functions read extra Lua arguments without allocation.

## Globals and tables

```zig
const globals = lua.globals();
try globals.set("x", 42);
const x = try globals.get("x", i32);

const table = lua.createTable(.{ .arr = 3, .rec = 2 });
defer table.deinit();
try table.setRaw(1, "one"); // raw: bypasses metamethods
try table.set("name", "demo");
const name = try table.get("name", []const u8);
```

Key table operations:

- `set` / `get` use full Lua semantics (metamethods honored).
- `setRaw` / `getRaw` bypass metamethods.
- `get` returns `error.KeyNotFound` for missing keys or failed conversions; use `?T` and `catch` to treat missing/nil as null.
- `len()` follows Lua `#` semantics (including `__len`).
- `iterator()` yields `Table.Entry` with `Lua.Value` key/value.
- `setReadonly`, `setSafeEnv`, `setMetaTable`, `getMetaTable`, `clear`, `clone`.
- `call("func", args, R)` calls a function stored in the table.

## Calling functions and using `Result`

Register Zig functions by storing them in globals or tables:

```zig
fn add(a: i32, b: i32) i32 { return a + b; }
try lua.globals().set("add", add);

const sum = try lua.eval("return add(10, 20)", .{}, i32);
std.debug.print("sum = {}\n", .{sum.ok.?});
```

Calling a Lua function via `Lua.Function`:

```zig
_ = try lua.eval("function mul(a, b) return a * b end", .{}, void);
const func = try lua.globals().get("mul", luaz.Lua.Function);
defer func.deinit();

const result = try func.call(.{ 6, 7 }, i32);
switch (result) {
    .ok => |value| std.debug.print("ok = {}\n", .{value.?}),
    .yield => |value| std.debug.print("yield = {}\n", .{value.?}),
    .debugBreak => std.debug.print("debug break\n", .{}),
}
```

## Captures, upvalues, and varargs

Use `Lua.Capture` to create closures with upvalues:

```zig
fn addWithOffset(upv: luaz.Lua.Upvalues(i32), x: i32) i32 {
    return x + upv.value;
}
try lua.globals().set("add5", luaz.Lua.Capture(@as(i32, 5), addWithOffset));
```

Use `Lua.Varargs` as the last parameter for variadic Lua calls:

```zig
fn sum(first: f64, args: luaz.Lua.Varargs) f64 {
    var total = first;
    var it = args;
    while (it.next(f64)) |n| total += n;
    return total;
}
try lua.globals().set("sum", sum);
```

## Userdata (binding Zig structs)

Register a struct and its public methods become Lua methods:

```zig
const Counter = struct {
    value: i32,
    pub fn init(start: i32) Counter { return .{ .value = start }; }
    pub fn increment(self: *Counter) void { self.value += 1; }
    pub fn getValue(self: Counter) i32 { return self.value; }
    pub fn __len(self: Counter) i32 { return self.value; } // metamethod
};

try lua.registerUserData(Counter);
_ = try lua.eval(
    \\local c = Counter.new(10)
    \\c:increment()
    \\print(c:getValue(), #c)
, .{}, void);
```

Notes:

- `init` becomes `new` in Lua.
- `deinit` (if present) is called by Lua GC.
- Metamethods use `__name` (for example, `__add`, `__tostring`).
- For custom metatables before registration, use `lua.createMetaTable(T)`.

## Coroutines and threads

`Lua.createThread()` creates a coroutine-capable state. Calling a function from a thread
uses resume semantics automatically, allowing `yield`:

```zig
_ = try lua.eval(
    \\function accumulator()
    \\  local sum = 0
    \\  while true do
    \\    local v = coroutine.yield(sum)
    \\    if v == nil then break end
    \\    sum = sum + v
    \\  end
    \\  return sum
    \\end
, .{}, void);

const thread = lua.createThread();
const func = try thread.globals().get("accumulator", luaz.Lua.Function);
defer func.deinit();

_ = try func.call(.{}, i32);        // yields 0
_ = try func.call(.{10}, i32);      // yields 10
const final = try func.call(.{@as(?i32, null)}, i32);
std.debug.print("final = {}\n", .{final.ok.?});
```

Other thread helpers:

- `status()`, `isYieldable()`
- `reset()` / `isReset()`
- `getData()` / `setData()` for thread-local pointers
- Threads are GC-managed; calling `deinit()` on a thread handle does not close the VM.

## Performance: codegen and compiler options

Enable JIT codegen once per state:

```zig
if (lua.enable_codegen()) {
    try lua.globals().compile("hot_function");
}
```

Relevant compiler options live in `Compiler.Opts`:

- `opt_level`: 0..2
- `dbg_level`: 0..2 (use 2 for locals and full debugging)
- `type_info_level`, `coverage_level`

## Binary data with `Buffer`

```zig
var buf = try lua.createBuffer(1024);
defer buf.deinit();
buf.data[0] = 0xFF;

var stream = buf.stream();
try stream.writer().writeInt(u32, 0x12345678, .little);
```

Buffers are fixed-size and managed by Lua GC; the `Buffer` wrapper holds a reference
so the memory stays alive until `deinit()`.

## Efficient strings with `StrBuf`

```zig
var buf: luaz.Lua.StrBuf = undefined;
buf.init(&lua);
buf.addString("User #");
try buf.add(@as(i32, 42));
buf.addString(" logged in");

try lua.globals().set("message", &buf);
```

Important: `StrBuf` must not be moved after `init`/`initSize`. Keep it as a local
variable and pass by pointer.

## Garbage collection and sandboxing

```zig
const gc = lua.gc();
gc.collect();
_ = gc.setGoal(150);

lua.sandbox(); // call after openLibs() and before executing untrusted code
```

The sandbox makes standard libs and globals read-only and enables safe envs.

## Callbacks and debugging

Use `lua.setCallbacks()` with a struct that implements any subset of callback methods:

- `onallocate`, `interrupt`, `panic`, `userthread`, `useratom`
- `debugbreak`, `debugstep`, `debuginterrupt`, `debugprotectederror`

Debugging flow:

1. Compile with `dbg_level = 2` (if you want locals/upvalues).
2. Set debug callbacks with `lua.setCallbacks(...)`.
3. Use `Function.setBreakpoint(line, enabled)` to set breakpoints.
4. In `debugbreak`, call `debug.debugBreak()` to interrupt execution.

`lua.debug()` provides stack inspection helpers (`stackDepth`, `getInfo`, `getArg`,
`getLocal`, `getUpvalue`) and `debugTrace()` for stack traces.

For quick inspection, `lua.dumpStack(allocator)` returns a formatted stack dump string.

## Low-level API and where to go deeper

- `lua.raw()` returns the low-level `State` wrapper for direct stack operations.
- Detailed API docs live in:
  - `src/Lua.zig` (high-level API and type conversions)
  - `src/State.zig` (raw C API bindings)
  - `src/Compiler.zig` (bytecode compiler)
  - `src/Debug.zig` (debugger API and flow)
  - `src/GC.zig` (GC controls)
- End-to-end examples:
  - `examples/guided_tour.zig`
  - `src/tests.zig` for additional patterns and edge cases

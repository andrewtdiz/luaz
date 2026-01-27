<p align="center">
  <img src="docs/logo.png" />
</p>

# luaz

[![CI](https://github.com/mxpv/luaz/actions/workflows/ci.yml/badge.svg)](https://github.com/mxpv/luaz/actions/workflows/ci.yml)
[![Docs](https://github.com/mxpv/luaz/actions/workflows/docs.yml/badge.svg)](https://github.com/mxpv/luaz/actions/workflows/docs.yml)
[![GitHub License](https://img.shields.io/github/license/mxpv/luaz)](./LICENSE)
[![codecov](https://codecov.io/gh/mxpv/luaz/branch/main/graph/badge.svg?token=GUTOF5TGFQ)](https://codecov.io/gh/mxpv/luaz)

Zero-cost Zig bindings for [`Luau`](https://github.com/luau-lang/luau), focused on Luau features (vectors, buffers, sandboxing, native codegen) with an idiomatic Zig API.

## Highlights

- High-level `Lua` API with automatic type conversion
- Low-level `State` wrapper (stack + raw C API coverage)
- `Compiler`, `Debug`, and `GC` modules
- Compile-time userdata bindings via `registerUserData(T)`
- Optional native codegen (JIT) on supported platforms
- Bundled tools: `luau-compile`, `luau-analyze`

## Docs & examples

- API docs: https://mxpv.github.io/luaz/#luaz
- Quick API notes: `LUAU_API.md`
- Guided tour: `examples/guided_tour.zig` (`zig build guided-tour`)

## Install

```bash
zig fetch --save git+https://github.com/mxpv/luaz.git#<tag-or-commit>
```

```zig
const luaz_dep = b.dependency("luaz", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("luaz", luaz_dep.module("luaz"));
```

## Quick start

```zig
const std = @import("std");
const luaz = @import("luaz");
const Lua = luaz.Lua;

pub fn main() !void {
    var lua = try Lua.init(null);
    defer lua.deinit();

    try lua.globals().set("x", @as(i32, 21));
    const res = try lua.eval("return x * 2", .{}, i32);
    std.debug.print("{}\n", .{res.ok.?});
}
```

## Codegen (JIT)

To use Luau's native code generator:
- Build with `-Dvector-size=3` (default). `-Dvector-size=4` disables codegen.
- At runtime: `if (lua.enable_codegen()) try lua.globals().compile("hot_function");`
- Consumers can force the build option via `b.dependency("luaz", .{ .@"vector-size" = 3, ... })`.

See `LUAU_API.md` for details and examples.

## Build

- Requires Zig `0.15.2+`
- `zig build test`
- `zig build guided-tour`
- `zig build luau-compile -- --help`
- `zig build luau-analyze -- --help`

## License

MIT. See `LICENSE`.

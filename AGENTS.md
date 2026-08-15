# AGENTS.md

## Lua/Luau syntax checks (ALWAYS do this)
After editing any `.lua` file in this repo, verify it compiles before committing:

1. Write/update `C:\Users\flint\AppData\Local\Temp\opencode\check_syntax.lua` with the changed file paths.
2. Run: `lune run "C:\Users\flint\AppData\Local\Temp\opencode\check_syntax.lua"`

`lune` is the only Luau toolchain installed (no `luau` or `lua` CLI). `loadstring()` only compiles, so it catches syntax errors without executing the game script.

## Shell gotchas (Windows PowerShell 5.1)
- `&&` and `||` are not supported. Chain with `cmd1; if ($?) { cmd2 }`.
- `$i:` in a string like `for ($i=0; ...)` fails ("' :' was not followed by a valid variable name character"). Use `${i}:`.
- Complex regex edits: write a `.ps1` script via the write tool, then run `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '<path>'"`.
- `git grep` is unreliable here. Prefer Select-String (ripgrep-based).

## Repo conventions
- Game scripts use Luau (`run(function() ... end)` blocks). Variable naming: camelCase locals.
- Never add code comments unless asked.
- Asset/config edits under `assets/` must keep `raw.githubusercontent.com/skidforce/skidv5/main/` URLs and the baked-id fallback maps (`getcustomassets[path]`) intact.

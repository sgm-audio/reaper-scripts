-- lua_smoke.lua — CI smoke test: run each ReaScript with a stubbed REAPER
-- environment to catch load-time/runtime crashes (e.g. calls to undefined
-- globals) that a syntax check cannot find.
--
-- Usage: lua5.4 tests/lua_smoke.lua <script.lua> [more.lua ...]
-- Exit codes: 0 = all ran clean, 2 = at least one runtime error.
-- (A timeout from the caller's `timeout` wrapper means the script waits on
--  real REAPER input under stubs — reported by CI as SKIP, not a failure.)

local function make_stub(name)
  local t = {}
  setmetatable(t, {
    __index = function(_, k) return make_stub(name .. "." .. tostring(k)) end,
    __call  = function(_, ...) return make_stub(name .. "()") end,
    __tostring = function() return name end,
    __concat = function(a, b) return tostring(a) .. tostring(b) end,
    __len = function() return 0 end,
    __unm = function() return 0 end,
    __add = function() return 0 end, __sub = function() return 0 end,
    __mul = function() return 0 end, __div = function() return 0 end,
    __mod = function() return 0 end, __pow = function() return 0 end,
    __idiv = function() return 0 end,
    __band = function() return 0 end, __bor = function() return 0 end,
    __bxor = function() return 0 end, __bnot = function() return 0 end,
    __shl = function() return 0 end, __shr = function() return 0 end,
    __eq = function() return false end,
    __lt = function() return false end, __le = function() return false end,
  })
  return t
end

reaper = make_stub("reaper")
gfx = make_stub("gfx")
ImGui = make_stub("ImGui")

local fail = 0
for _, f in ipairs(arg) do
  local fh = assert(io.open(f, "rb"))
  local src = fh:read("*a"); fh:close()
  local chunk, err = load(src, "@" .. f)
  if not chunk then
    print("LOAD-FAIL " .. f .. ": " .. tostring(err)); fail = 2
  else
    local ok, rerr = pcall(chunk)
    if ok then
      print("RUN-OK   " .. f)
    else
      print("RUN-FAIL " .. f .. ": " .. tostring(rerr)); fail = 2
    end
  end
end
os.exit(fail)

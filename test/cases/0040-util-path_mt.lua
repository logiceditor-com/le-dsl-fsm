--------------------------------------------------------------------------------
-- 0040-util-path_mt.lua: Tests for path-based DSL walker hook micro-language
-- This file is a part of le-dsl-fsm project
-- Copyright (c) LogicEditor <info@logiceditor.com>
-- Copyright (c) le-dsl-fsm authors
-- See file `COPYRIGHT` for the license.
--------------------------------------------------------------------------------

local log, dbg, spam, log_error
      = import 'lua-aplicado/log.lua' { 'make_loggers' } (
          "dsl-fsm/test/util-path_mt", "0040"
        )

--------------------------------------------------------------------------------

local ensure,
      ensure_equals,
      ensure_tdeepequals,
      ensure_returns
      = import 'lua-nucleo/ensure.lua'
      {
        'ensure',
        'ensure_equals',
        'ensure_tdeepequals',
        'ensure_returns'
      }

local tstr
      = import 'lua-nucleo/tstr.lua'
      {
        'tstr'
      }

local tclone
      = import 'lua-nucleo/table-utils.lua'
      {
        'tclone'
      }

local make_path_based_walker
      = import 'lua-nucleo/dsl/path_based_walker.lua'
      {
        'make_path_based_walker'
      }

--------------------------------------------------------------------------------

local create_path_mt,
      imports
      = import 'dsl-fsm/util/path_mt.lua'
      {
        'create_path_mt'
      }

--------------------------------------------------------------------------------

local test = (...)("dsl-fsm-dsl_bootstrap", imports)

--------------------------------------------------------------------------------

test:tests_for "create_path_mt"

--------------------------------------------------------------------------------

-- NOTE: A *very* basic test.
test "smoke" (function()
  local log = { }

  local rules = { }

  rules.down, rules.up = ensure(
      "create path mt",
      create_path_mt(function()
        on
        {
          "alpha"; "beta";
          function(path)
            log[#log + 1] = { "path", path }
            return true
          end
        }
        : down(function(self, t)
          ensure_equals("down self", self, rules)
          log[#log + 1] = { "down", tclone(t) }
          return #log
        end)
        : up(function(self, t)
          ensure_equals("up self", self, rules)
          log[#log + 1] = { "up", tclone(t) }
          return #log
        end)
      end)
    )

  local calls =
  {
    { "down", { "alpha", "beta", "gamma" }, { "gamma-v" } };
    { "up", { "alpha", "beta", "gamma" }, { "gamma-v" } };
  }

  for i = 1, #calls do
    local dir = ensure("dir `" .. calls[i][1] .. "'", rules[calls[i][1]])
    local handler = ensure(
        "handler `"  .. calls[i][1] .. "' `" .. tstr(calls[i][2]) .. "'",
        dir[calls[i][2]]
      )
    ensure_returns(
        "return value",
        1, { #log + 1 },
        handler(rules, calls[i][3])
      )
  end

  ensure_tdeepequals(
      "call log",
      log,
      {
        { "path", "gamma" };
        { "down", { "gamma-v" } };
        { "path", "gamma" };
        { "up", { "gamma-v" } };
      }
    )
end)

--------------------------------------------------------------------------------

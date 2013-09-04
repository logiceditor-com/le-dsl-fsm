--------------------------------------------------------------------------------
-- 0020-common_env.lua: DSL FSM builder tests for common_env
-- This file is a part of le-dsl-fsm project
-- Copyright (c) LogicEditor <info@logiceditor.com>
-- Copyright (c) le-dsl-fsm authors
-- See file `COPYRIGHT` for the license.
--------------------------------------------------------------------------------

local log, dbg, spam, log_error
      = import 'lua-aplicado/log.lua' { 'make_loggers' } (
          "dsl-fsm/test/common_env", "0020"
        )

--------------------------------------------------------------------------------

local select, rawset, tostring, error, unpack, setmetatable, assert
    = select, rawset, tostring, error, unpack, setmetatable, assert

--------------------------------------------------------------------------------

local ensure_tequals,
      ensure_tdeepequals,
      ensure_fails_with_substring,
      ensure_error_with_substring,
      ensure_is,
      ensure,
      ensure_equals,
      ensure_strequals,
      ensure_returns
      = import 'lua-nucleo/ensure.lua'
      {
        'ensure_tequals',
        'ensure_tdeepequals',
        'ensure_fails_with_substring',
        'ensure_error_with_substring',
        'ensure_is',
        'ensure',
        'ensure_equals',
        'ensure_strequals',
        'ensure_returns'
      }

local is_string,
      is_table
      = import 'lua-nucleo/type.lua'
      {
        'is_string',
        'is_table'
      }

local do_in_environment
      = import 'lua-nucleo/sandbox.lua'
      {
        'do_in_environment'
      }

local tstr
      = import 'lua-nucleo/tstr.lua'
      {
        'tstr'
      }

local tset
      = import 'lua-nucleo/table-utils.lua'
      {
        'tset'
      }

local capture_source_location
      = import 'lua-nucleo/diagnostics.lua'
      {
        'capture_source_location'
      }

--------------------------------------------------------------------------------

local create_dsl_env_mt,
      do_in_common_dsl_environment
      = import 'dsl-fsm/common_env.lua'
      {
        'create_dsl_env_mt',
        'do_in_common_dsl_environment'
      }

--------------------------------------------------------------------------------

local test = (...)("dsl-fsm-common-env")

--------------------------------------------------------------------------------

test "common-env-contexts-shared" (function()
  local contexts = { }

  local init = function(proxy)
    (-proxy)._add_states
    {
      {
        type = "call"; id = "()";
        from_init = true;

        false;

        handler = function(self, t)
          contexts[#contexts + 1] = self:context()
        end;
      };
    }
  end

  ensure(
      "run dsl",
      do_in_common_dsl_environment(function()
        init(alpha)
        init(beta)
        init(-gamma)

        alpha()
        alpha()
        beta()
        beta()
        ;(-gamma)()
        ;(-gamma)()
        ;(-delta)()
        ;(-delta)()
      end)
    )

  ensure_equals("number of contexts", #contexts, 8)

  local c = contexts[1]
  for i = 2, #contexts do
    ensure_equals(i .. ": context should be the same", contexts[i], c)
  end
end)

--------------------------------------------------------------------------------

test "common-env-extra-context" (function()
  local tag = { called = false }

  local init = function(proxy)
    (-proxy)._add_states
    {
      {
        type = "call"; id = "()";
        from_init = true;

        false;

        handler = function(self, t)
          ensure_equals(
              "extra context visible",
              self:context().tag,
              tag
            )
          self:context().tag.called = true
          self:context().not_shared = true
        end;
      };
    }
  end

  local extra_context = { tag = tag }

  ensure(
      "run dsl",
      do_in_common_dsl_environment(
          function()
            init(alpha)
            alpha()
          end,
          { },
          create_dsl_env_mt(tset { "alpha" }, extra_context)
        )
    )

  -- TODO: Not sure if it is a feature.
  ensure_equals("context not shared", extra_context.not_shared, nil)

  ensure_tdeepequals(
      "handler called",
      extra_context,
      { tag = { called = true } }
    )
end)

--------------------------------------------------------------------------------

-- TODO: Remove this restriction.
-- TODO: Hide system keys altogether.
test "common-env-extra-context-reserved-names" (function()
  ensure_fails_with_substring(
      "run dsl",
      function()
        do_in_common_dsl_environment(
            function() end,
            { },
            create_dsl_env_mt(tset { "alpha" }, { dsl_env = true })
          )
      end,
      [[can't override system context key `dsl_env']]
    )
end)

--------------------------------------------------------------------------------

test "common-env-basic" (function()

  local call_log = ""
  local create_call = function(proxy, namespace, tag, need_final)
    if need_final == nil then
      need_final = true
    end

    local index_state_id = namespace .. "." .. tag
    local call_state_id = namespace .. ":" .. tag .. "(param)"

    (-proxy)._add_states
    {
      {
        type = "index"; id = index_state_id;
        from_init = true;

        value = tag;
      };
      {
        type = "call"; id = call_state_id;
        from = index_state_id;

        false;

        handler = function(self, t, _, param)
          self:ensure_method_call(_)
          self:ensure_is("param", param, "string")
          if self:good() then
            call_log = call_log
              .. namespace .. ":" .. tag .. "(" .. param .. ");"
          end
        end;
      };
      -- Should be last one
      need_final
        and
        {
          type = "final"; id = false;
          from = call_state_id;

          handler = function(self, t)
            return t
          end;
        }
        or nil
        ;
    }

    return call_log
  end

  local check = function(msg, dsl_chunk, expected_result, expected_call_log)
    assert(call_log == "")
    local result = ensure(
        msg .. " do in common dsl environment run",
        do_in_common_dsl_environment(dsl_chunk)
      )
    ensure_strequals(
        msg .. " call log matches expected", call_log, expected_call_log
      )
    ensure_tdeepequals(
        msg .. " result matches expected",
        result,
        expected_result
      )
    call_log = ""
  end

  check(
      "minimal",
      function()
        create_call(alpha, "alpha", "beta")
        alpha:beta [[gamma]]
      end,
      { },
      "alpha:beta(gamma);"
    )

  ensure_error_with_substring(
      "other DSL not affected",
      [[unexpected index state transition attempt from `(init)',]] ..
      [[ by index `beta', expected one of { -delta }]],
      do_in_common_dsl_environment(function()
        create_call(alpha, "alpha", "beta")
        delta:beta [["gamma"]]
      end)
    )

  check(
      "two different dsls",
      function()
        create_call(alpha, "alpha", "beta")
        create_call(delta, "delta", "epsilon")
        alpha:beta [[gamma]]
        delta:epsilon [[zeta]]
      end,
      { },
      "alpha:beta(gamma);delta:epsilon(zeta);"
    )

  check(
      "meta changed",
      function()
        create_call(-alpha, "(-dsl)", "beta", false)
        ;(-alpha):beta [[gamma]]
      end,
      { },
      "(-dsl):beta(gamma);" -- TODO: Check log from meta as well.
    )

  ensure_error_with_substring(
      "non-meta DSL not affected when meta changed",
      [[unexpected index state transition attempt from `(init)',]] ..
      [[ by index `beta', expected one of { -alpha }]],
      do_in_common_dsl_environment(function()
        create_call(-alpha, "(-dsl)", "beta", false)
        alpha:beta [[gamma]]
      end)
    )

  check(
      "-beta knows about -alpha",
      function()
        create_call(-alpha, "(-dsl)", "beta", false)
        ;(-beta):beta [[delta]]
      end,
      { },
      "(-dsl):beta(delta);"
    )

  -- Based on actual bug scenario.
  check(
      "-alpha does not know about alpha",
      function()
        create_call(alpha, "alpha", "beta")
        -- intentional namespace reuse
        create_call(-alpha, "alpha", "beta", false)
        ;(-alpha):beta [[gamma]]
        alpha:beta [[delta]]
      end,
      { },
      "alpha:beta(gamma);alpha:beta(delta);"
    )

  -- Based on actual bug scenario.
  ensure_error_with_substring(
      "duplicate index fields in the same state are caught by validation",
      [[bad fsm `alpha' init: contains more than one reference to value]] ..
      [[ `beta' (found `alpha2.beta', but already seen `alpha1.beta')]],
      do_in_common_dsl_environment(function()
        -- Note different namespace names
        create_call(alpha, "alpha1", "beta")
        create_call(alpha, "alpha2", "beta", false)
      end)
    )

  check(
      "extra finalizers",
      function()
        create_call(alpha, "alpha", "beta")
        ;(-alpha)._add_states
        {
          {
            type = "final"; id = false;

            handler = function(self, t)
              call_log = call_log .. self:namespace() .. ".finalizer1;"
            end
          };
        }
        ;(-alpha)._add_states
        {
          {
            type = "final"; id = false;

            handler = function(self, t)
              call_log = call_log .. self:namespace() .. ".finalizer2;"
            end
          };
        }
        alpha:beta [[gamma]]
      end,
      { },
      "alpha:beta(gamma);alpha.finalizer1;alpha.finalizer2;"
    )

  check(
      "extra finalizers for meta",
      function()
        create_call(-alpha, "(-dsl)", "beta")
        ;(-(-alpha))._add_states
        {
          {
            type = "final"; id = false;

            handler = function(self, t)
              call_log = call_log .. self:namespace() .. ".finalizer1;"
            end
          };
        }
        ;(-(-alpha))._add_states
        {
          {
            type = "final"; id = false;

            handler = function(self, t)
              call_log = call_log .. self:namespace() .. ".finalizer2;"
            end
          };
        }
        ;(-beta):beta [[gamma]]
      end,
      { },
      "(-dsl):beta(gamma);(-dsl).finalizer1;(-dsl).finalizer2;"
      -- Extra finalizers from (-alpha) calls
      .. "(-dsl).finalizer1;(-dsl).finalizer2;"
      .. "(-dsl).finalizer1;(-dsl).finalizer2;"
      .. "(-dsl).finalizer1;(-dsl).finalizer2;"
    )

  -- Based on actual bug scenario.
  ensure_error_with_substring(
      "double finalization diagnostics",
      [[attempt to call local 'proxy' (a table value)]],
      do_in_common_dsl_environment(function()
        create_call(alpha, "alpha", "beta")
        local proxy = alpha.beta
        proxy(proxy, [[gamma]])
        proxy(proxy, [[delta]])
      end)
    )
end)

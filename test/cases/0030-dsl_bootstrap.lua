--------------------------------------------------------------------------------
-- 0030-dsl_bootstrap.lua: DSL FSM builder tests for DSL bootstrap
-- This file is a part of le-dsl-fsm project
-- Copyright (c) LogicEditor <info@logiceditor.com>
-- Copyright (c) le-dsl-fsm authors
-- See file `COPYRIGHT` for the license.
--------------------------------------------------------------------------------

local log, dbg, spam, log_error
      = import 'lua-aplicado/log.lua' { 'make_loggers' } (
          "dsl-fsm/test/dsl_bootstrap", "0030"
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

local make_dsl_manager
      = import 'dsl-fsm/dsl_manager.lua'
      {
        'make_dsl_manager'
      }

local create_dsl_env_mt,
      do_in_common_dsl_environment
      = import 'dsl-fsm/common_env.lua'
      {
        'create_dsl_env_mt',
        'do_in_common_dsl_environment'
      }

local dsl_fsm_bootstrap_chunk
      = import 'dsl-fsm/bootstrap.lua'
      {
        'dsl_fsm_bootstrap_chunk'
      }

--------------------------------------------------------------------------------

local test = (...)("dsl-fsm-dsl_bootstrap")

--------------------------------------------------------------------------------

test "common-env-bootstrap" (function()
  local check = function(msg, dsl_chunk, expected_result)
    local result = ensure(
        msg .. " do in common dsl environment run",
        do_in_common_dsl_environment(
            { dsl_fsm_bootstrap_chunk, dsl_chunk },
            { },
            create_dsl_env_mt(tset { "_", "alpha" })
          )
      )
    ensure_tdeepequals(
        msg .. " result matches expected",
        result,
        expected_result
      )
  end

  do
    -- TODO: Test not only _index, others too
    ensure_error_with_substring(
        "_index without apply_to fails on finalization",
        [[unfinished dsl construct]]
        .. [[ (can't be finalized in `(-dsl)._index{param}' state)]],
        do_in_common_dsl_environment
        {
          dsl_fsm_bootstrap_chunk;
          function()
            (-_)._index
            {
              id = "alpha.beta";
              from_init = true;

              false;

              value = "beta";
            }
          end;
        }
      )
  end

  do
    local handler_called = false
    check(
        "_index",
        function()
          (-_)._index
          {
            id = "alpha.beta";
            from_init = true;

            false;

            value = "beta";

            handler = function(self, t)
              handler_called = true
            end;
          }.apply_to(-alpha)

          local _ = alpha.beta
        end,
        { }
      )
    ensure("handler called", handler_called)
  end

  do
    local handler_called = false
    check(
        "_call",
        function()
          (-_)._call
          {
            id = "alpha()";
            from_init = true;

            false;

            handler = function(self, t, v)
              ensure_equals("value", v, 42)
              handler_called = true
            end;
          }.apply_to(-alpha)

          local _ = alpha(42)
        end,
        { }
      )
    ensure("handler called", handler_called)
  end

  do
    local handler_called = false
    check(
        "_field_call",
        function()
          (-_)._field_call
          {
            id = "alpha.beta";
            from_init = true;

            false;

            value = "beta";

            handler = function(self, t, v)
              ensure("field call", not self:is_self(v))
              ensure_equals("value", v, 42)
              handler_called = true
            end;
          }.apply_to(-alpha)

          local _ = alpha.beta(42)
        end,
        { }
      )
    ensure("handler called", handler_called)
  end

  do
    local handler_called = false
    check(
        "_method_call",
        function()
          (-_)._method_call
          {
            id = "alpha:beta";
            from_init = true;

            false;

            value = "beta";

            handler = function(self, t, _, v)
              ensure("method call", self:is_self(_))
              ensure_equals("value", v, 42)
              handler_called = true
            end;
          }.apply_to(-alpha)

          local _ = alpha:beta(42)
        end,
        { }
      )
    ensure("handler called", handler_called)
  end

  do
    local call_log = ""
    check(
        "_extension",
        function()
          (-_)._extension
          {
            (-_)
              ._field_call
              {
                id = "alpha.beta";
                from_init = true;

                "alpha.beta().delta";

                value = "beta";

                handler = function(self, t, v)
                  call_log = call_log
                    .. self:namespace() .. ".beta(" .. tostring(v) .. ")"
                end;
              }
              ._index
              {
                id = "alpha.beta().delta";
                from = "alpha.beta()";

                false;

                value = "delta";

                handler = function(self, t)
                  call_log = call_log .. ".delta;"
                end;
              };
            (-_)
              ._method_call
              {
                id = "alpha:epsilon";
                from_init = true;

                false;

                value = "epsilon";

                handler = function(self, t, _, v)
                  call_log = call_log
                    .. self:namespace() .. ":epsilon(" .. tostring(v) .. ")"
                end;
              }
          }.apply_to(-alpha)

          local _ = alpha.beta(42).delta
          alpha:epsilon "foo"
        end,
        { }
      )
    ensure_strequals(
        "call log",
        call_log,
        [[alpha.beta(42).delta;alpha:epsilon(foo)]]
      )
  end

  do
    local call_log = ""
    check(
        "_extend",
        function()
          (-alpha)._extend
          {
            (-_)
              ._field_call
              {
                id = "alpha.beta";
                from_init = true;

                "alpha.beta().delta";

                value = "beta";

                handler = function(self, t, v)
                  call_log = call_log
                    .. self:namespace() .. ".beta(" .. tostring(v) .. ")"
                end;
              }
              ._index
              {
                id = "alpha.beta().delta";
                from = "alpha.beta()";

                false;

                value = "delta";

                handler = function(self, t)
                  call_log = call_log .. ".delta;"
                end;
              };
            (-_)
              ._method_call
              {
                id = "alpha:epsilon";
                from_init = true;

                false;

                value = "epsilon";

                handler = function(self, t, _, v)
                  call_log = call_log
                    .. self:namespace() .. ":epsilon(" .. tostring(v) .. ")"
                end;
              };
          }

          local _ = alpha.beta(42).delta
          alpha:epsilon "foo"
        end,
        { }
      )
    ensure_strequals(
        "call log",
        call_log,
        [[alpha.beta(42).delta;alpha:epsilon(foo)]]
      )
  end
end)

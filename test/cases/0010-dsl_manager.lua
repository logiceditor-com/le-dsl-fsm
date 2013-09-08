--------------------------------------------------------------------------------
-- 0010-dsl_manager.lua: DSL FSM builder tests for dsl_manager
-- This file is a part of le-dsl-fsm project
-- Copyright (c) LogicEditor <info@logiceditor.com>
-- Copyright (c) le-dsl-fsm authors
-- See file `COPYRIGHT` for the license.
--------------------------------------------------------------------------------

local log, dbg, spam, log_error
      = import 'lua-aplicado/log.lua' { 'make_loggers' } (
          "dsl-fsm/test/dsl_manager", "0010"
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
      ensure_returns,
      ensure_has_substring
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
        'ensure_returns',
        'ensure_has_substring'
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

--------------------------------------------------------------------------------

local test = (...)("dsl-fsm-dsl_manager")

--------------------------------------------------------------------------------

test "minimal" (function()

  local fsm_object = nil
  local data_object = nil

  local finalizer_called = false
  local min_root_called = false
  local min_root_id_called = false

  local fsm =
  {
    id = "min";

    factory = function()
      ensure_equals("fsm_object created once in this test", fsm_object, nil)

      fsm_object =
      {
        min_fsm_ = true;
      }

      return fsm_object
    end;

    init =
    {
      "min:root";

      handler = function(self)
        ensure("fsm_object was created", fsm_object)
        ensure_equals("self is fsm_object", self, fsm_object)
        ensure_equals("data_object created once in this test", data_object, nil)

        data_object =
        {
          init = true;
          log = "init;"
        }

        return data_object
      end;
    };

    states =
    {
      [false] =
      {
        type = "final", id = false;

        handler = function(self, t, data)
          ensure_equals("prev state id", self:prev_state_id(), "min:root.id")

          ensure("fsm_object was created", fsm_object)
          ensure("data_object was created", data_object)
          ensure_equals("self is fsm_object", self, fsm_object)
          ensure_equals("t is data_object", t, data_object)
          ensure_equals("data is nil in final state", data, nil)

          ensure("finalizer called once in this test", not finalizer_called)
          finalizer_called = true

          ensure_strequals("t call log", t.log, "init;min_root;min_root_id;")
          ensure_equals("t init overridden", t.init, nil)
          ensure_equals("t min_root overridden", t.min_root, nil)
          ensure_equals("t min_root_id just called", t.min_root_id, true)
          ensure_equals("t final not yet called", t.final, nil)

          data_object = { final = true; log = t.log .. "final;" }

          return data_object
        end;
      };

      ["min:root"] =
      {
        type = "index", id = "min:root";

        "min:root.id";

        value = "root";

        handler = function(self, t, data)
          ensure_equals("prev state id", self:prev_state_id(), nil)

          ensure("fsm_object was created", fsm_object)
          ensure("data_object was created", data_object)
          ensure_equals("self is fsm_object", self, fsm_object)
          ensure_equals("t is data_object", t, data_object)
          ensure_strequals("data is `root' in min:root state", data, "root")

          ensure(
              "min:root called once in this test",
              not min_root_called
            )
          min_root_called = true

          ensure_strequals("t call log", t.log, "init;")
          ensure_equals("t init just called", t.init, true)
          ensure_equals("t min_root not yet called", t.min_root, nil)
          ensure_equals("t min_root_id not yet called", t.min_root_id, nil)
          ensure_equals("t final not yet called", t.final, nil)

          data_object = { min_root = true; log = t.log .. "min_root;" }

          return data_object
        end;
      };

      ["min:root.id"] =
      {
        type = "call", id = "min:root.id";

        false;

        handler = function(self, t, data)
          ensure_equals("prev state id", self:prev_state_id(), "min:root")

          ensure("fsm_object was created", fsm_object)
          ensure("data_object was created", data_object)
          ensure_equals("self is fsm_object", self, fsm_object)
          ensure_equals("t is data_object", t, data_object)
          ensure_strequals("data is `myid' in min:root.id state", data, "myid")

          ensure(
              "min:root.id called once in this test",
              not min_root_id_called
            )
          min_root_id_called = true

          ensure_strequals("t call log", t.log, "init;min_root;")
          ensure_equals("t init overridden", t.init, nil)
          ensure_equals("t min_root just called", t.min_root, true)
          ensure_equals("t min_root_id not yet called", t.min_root_id, nil)
          ensure_equals("t final not yet called", t.final, nil)

          data_object = { min_root_id = true; log = t.log .. "min_root_id;" }

          return data_object
        end;
      };
    };
  }

  local dsl_manager = ensure("manager created", make_dsl_manager(fsm))
  local proxy = ensure("proxy created", dsl_manager:proxy("min"))
  ensure("manager is good after init", dsl_manager:good())

  local result = proxy.root "myid"

  ensure("manager still good", dsl_manager:finalize())

  ensure("fsm_object was created", fsm_object)
  ensure("data_object was created", data_object)
  ensure("finalizer was called", finalizer_called)
  ensure("min:root was called", min_root_called)
  ensure("min:root.id was called", min_root_id_called)

  ensure_tdeepequals(
      "data_object matches expected",
      data_object,
      {
        final = true;
        log = "init;min_root;min_root_id;final;";
      }
    )

  ensure_tdeepequals(
      "result matches data_object",
      result,
      data_object
    )

  -- No reference equality guarantees for data_object and result.

end)

--------------------------------------------------------------------------------

test "at" (function()

  local ats = { }

  local fsm =
  {
    id = "at";

    init =
    {
      "at:root";

      handler = function(self)
        ats["init"] = self:at()
        return { }
      end;
    };

    states =
    {
      [false] =
      {
        type = "final", id = false;

        handler = function(self, t, data)
          ats["final"] = self:at()
        end;
      };

      ["at:root"] =
      {
        type = "index", id = "at:root";

        "at:root()";

        value = "root";

        handler = function(self, t, data)
          ats["at:root"] = self:at()
        end;
      };

      -- TODO: Test unm as well.
      ["at:root()"] =
      {
        type = "call", id = "at:root()";

        false;

        handler = function(self, t, data)
          ats["at:root()"] = self:at()
        end;
      };
    };
  }

  ensure(
      "run",
      do_in_environment(
          ensure(
              "load",
              loadstring(
                  [[DSL:proxy("at"):root()]],
                   "=at-location-marker"
                )
            ),
          {
            DSL = ensure("create dsl manager", make_dsl_manager(fsm));
          }
        )
    )

  ensure_has_substring(
      "init",
      tostring(ensure("have ats[init]", ats["init"])("error-message-marker")),
      "at-location-marker:1: error-message-marker"
    )

  ensure_has_substring(
      "at:root",
      tostring(
          ensure("have ats[at:root]", ats["at:root"])("error-message-marker")
        ),
      "at-location-marker:1: error-message-marker"
    )

  ensure_has_substring(
      "at:root()",
      tostring(
          ensure(
              "have ats[at:root()]",
              ats["at:root()"]
            )("error-message-marker")
        ),
      "at-location-marker:1: error-message-marker"
    )

end)

--------------------------------------------------------------------------------

test "forced-finalization" (function()

  local fsm =
  {
    id = "reg";

    init =
    {
      "reg:index";

      handler = function(self)
        return { log = "init;" }
      end;
    };

    states =
    {
      [false] =
      {
        type = "final", id = false;

        handler = function(self, t)
          return { log = t.log .. "final;" }
        end;
      };

      ["reg:index"] =
      {
        type = "index", id = "reg:index";

        "reg:index"; -- Note loop
        false;

        value = "index";

        handler = function(self, t, k)
          return { log = t.log .. "index;" }
        end;
      };
    };
  }

  local dsl_manager = ensure("manager created", make_dsl_manager(fsm))
  local proxy = ensure("proxy created", dsl_manager:proxy("reg"))

  local result = proxy.index.index.index

  ensure("finalize manager", dsl_manager:finalize())

  ensure_tdeepequals(
      "result matches expected",
      result,
      {
        log = "init;index;index;index;final;";
      }
    )
end)

--------------------------------------------------------------------------------

test "store-finalized-data" (function()

  local fsm =
  {
    id = "fin";

    init =
    {
      "fin()";
      "fin.index";
    };

    states =
    {
      [false] = true;

      ["fin()"] =
      {
        type = "call", id = "fin()";

        false;

        handler = function(self, t, store, value)
          if store then
            self:store_finalized_data()
          end
          return { value = value }
        end;
      };

      ["fin.index"] =
      {
        type = "index", id = "fin.index";

        "fin()"; -- Uncertainty to forbid auto-finalization.
        false;

        value = "index";

        handler = function(self, t, k)
          return { value = "index" }
        end;
      };
    };
  }

  local dsl_manager = ensure("manager created", make_dsl_manager(fsm))

  ensure_tdeepequals(
      "auto-finalized",
      ensure("proxy created", dsl_manager:proxy("fin"))(true, "finalized 1"),
      {
        value = "finalized 1";
      }
    )

  ensure_tdeepequals(
      "auto-finalized",
      ensure("proxy created", dsl_manager:proxy("fin"))(false, "not finalized"),
      {
        value = "not finalized"
      }
    )

  do
    local proxy = ensure("proxy created", dsl_manager:proxy("fin"))
    ensure_equals(
        "not auto-finalized",
        proxy.index,
        proxy
      )
  end

  ensure_tdeepequals(
      "auto-finalized",
      ensure("proxy created", dsl_manager:proxy("fin")).index(
          true,
          "finalized 2"
        ),
      {
        value = "finalized 2";
      }
    )

  ensure_tdeepequals(
      "finalization result matches expected",
      ensure("finalize manager", dsl_manager:finalize()),
      {
        -- Note: creation time order is important here.
        { value = "finalized 1" };
        { value = "index" };
        { value = "finalized 2" };
      }
    )
end)

--------------------------------------------------------------------------------

test "two-instances" (function()

  local num_factories = 0

  local fsm =
  {
    id = "two";

    factory = function()
      num_factories = num_factories + 1
      return { n = num_factories }
    end;

    init =
    {
      "two:index";

      handler = function(self)
        return { log = "init(" .. self.n .. ");" }
      end;
    };

    states =
    {
      [false] =
      {
        type = "final", id = false;

        handler = function(self, t)
          t.log = t.log .. "final(" .. self.n .. ");"
        end;
      };

      ["two:index"] =
      {
        type = "index", id = "two:index";

        "two:call";

        value = "index";

        handler = function(self, t, k)
          t.log = t.log .. "index(" .. self.n .. ");"
        end;
      };

      ["two:call"] =
      {
        type = "call", id = "two:call";

        false;

        handler = function(self, t, v)
          t.log = t.log .. "call(" .. self.n .. ");"
          t.v = v
        end;
      };
    };
  }

  local dsl_manager1 = ensure("manager1 created", make_dsl_manager(fsm))
  local proxy1 = ensure("proxy1 created", dsl_manager1:proxy("one"))

  local dsl_manager2 = ensure("manager1 created", make_dsl_manager(fsm))
  local proxy2 = ensure("proxy1 created", dsl_manager2:proxy("two"))

  local result1 = proxy1.index(
      ensure("proxy2.1 created", dsl_manager2:proxy("three")).index()
    )
  local result2 = proxy2.index(
      ensure("proxy1.1 created", dsl_manager1:proxy("four")).index()
    )

  ensure("finalize manager1", dsl_manager1:finalize())
  ensure("finalize manager2", dsl_manager2:finalize())

  ensure_tdeepequals(
      "result1 matches expected",
      result1,
      {
        log = "init(1);index(1);call(1);final(1);";
        v =
        {
          log = "init(3);index(3);call(3);final(3);";
        };
      }
    )

  ensure_tdeepequals(
      "result2 matches expected",
      result2,
      {
        log = "init(2);index(2);call(2);final(2);";
        v =
        {
          log = "init(4);index(4);call(4);final(4);";
        };
      }
    )

  ensure_equals("factories, total", num_factories, 4)
end)

--------------------------------------------------------------------------------

test "arg-finalization" (function()

  local fsm =
  {
    id = "af";

    init =
    {
      "af:call";

      handler = function(self)
        return { log = "{" }
      end;
    };

    states =
    {
      [false] =
      {
        type = "final", id = false;

        handler = function(self, t)
          t.log = t.log .. "}"
        end;
      };

      ["af:call"] =
      {
        type = "call", id = "af:call";

        "af:call";
        false;

        handler = function(self, t, v)
          t.log = t.log .. "call(" .. (is_table(v) and v.log or v) .. ");"
        end;
      };
    };
  }

  local dsl_manager = ensure("manager created", make_dsl_manager(fsm))

  local result = ensure("proxy created", dsl_manager:proxy("one"))(
      42
    )(
      ensure("proxy created", dsl_manager:proxy("two"))("inner")
    )(
      24
    )

  ensure("finalize manager", dsl_manager:finalize())

  ensure_tdeepequals(
      "result matches expected",
      result,
      {
        log = "{"
           .. "call(42);"
           .. "call({call(inner);});"
           .. "call(24);"
           .. "}"
            ;
      }
    )
end)

--------------------------------------------------------------------------------

test "arg-subtable-finalization" (function()

  local fsm =
  {
    id = "af";

    init =
    {
      "af:call";

      handler = function(self)
        return { log = "<" }
      end;
    };

    states =
    {
      [false] =
      {
        type = "final", id = false;

        handler = function(self, t)
          t.log = t.log .. ">"
        end;
      };

      ["af:call"] =
      {
        type = "call", id = "af:call";

        "af:call";
        false;

        handler = function(self, t, v)
          t.log = t.log .. "call(" .. tstr(is_table(v) and v.log or v) .. ");"
        end;
      };
    };
  }

  local dsl_manager = ensure("manager created", make_dsl_manager(fsm))

  local result = ensure("proxy created", dsl_manager:proxy("one"))(
      42
    ){
      foo = ensure("proxy created", dsl_manager:proxy("two"))("inner")
    }(
      24
    )

  ensure("finalize manager", dsl_manager:finalize())

  ensure_tdeepequals(
      "result matches expected",
      result,
      {
        log = "<"
           .. "call(42);"
           .. "call({"
           ..   "foo={"
           ..     'log="<call(\\"inner\\");>"'
           ..   "}"
           .. "});"
           .. "call(24);"
           .. ">"
            ;
      }
    )
end)

--------------------------------------------------------------------------------

test "autodsl-showcase" (function()
  local fsm =
  {
    id = "auto";

    factory = function()

      return
      {
        key_ = "name";
      }
    end;

    init =
    {
      "*:index";
      "*:call";
    };

    states =
    {
      [false] = true; -- Have final state.

      ["*:index"] =
      {
        type = "index", id = "*:index";

        "*:index";
        "*:call";
        false;

        value = function(self, t, k) return true end; -- catchall

        handler = function(self, t, k)
          self.key_ = k
        end;
      };

      ["*:call"] =
      {
        type = "call", id = "*:call";

        "*:index";
        "*:call";
        false;

        -- Note: dumb implementation, not suitable for production.
        handler = function(self, t, ...)
          local is_method_call = self:is_self((...))

          if t.id == nil then
            if is_method_call then
              local _, name = ...
              self:ensure(
                  "a single name argument is expected",
                  select("#", ...) == 2
                )
              self:ensure_is("name argument must be string", name, "string")
              self:ensure_is("type must be string", self.key_, "string")
              t.id = self:namespace() .. ":" .. tostring(self.key_)
              t.name = name
              self.key_ = 1

              return -- extracted all data we wanted
            else
              t.id = self:namespace()
              t.name = nil -- no name
              self.key_ = 1
            end
          end

          -- Skip self for method calls.
          local base = is_method_call and 1 or 0

          local nargs = select("#", ...) - base

          local value
          if nargs == 0 then
            value = nil
          elseif nargs == 1 then
            value = select(base + 1, ...)
          else
            value = { n = nargs, select(base + 1, ...) }
          end

          local k = self.key_
          if t[k] == nil then
            t[k] = value
          elseif not is_table(t[k]) then
            t[k] = { t[k], value }
          else
            t[k][#t[k] + 1] = value
          end

          self.key_ = 1
        end
      };
    };
  }

  local manager = ensure("manager created", make_dsl_manager(fsm))

  local env = setmetatable(
      { },
      {
        __index = function(t, k)
          if not is_string(k) then
            return nil
          end

          -- Intentionally not caching, proxies are not reusable.
          return ensure(
              "proxy created",
              manager:proxy(k, capture_source_location(2))
            )
        end;

        __newindex = function(t, k, v)
          error("globals are read-only", 2)
        end;
      }
    )

  ensure(
      "run dsl",
      do_in_environment(
          function()
            alpha:beta "gamma"

            delta (42) { data = true }

            delta( alpha.epsilon (1) )
          end,
          env
        )
    )

  local result = ensure("finalize", manager:finalize())

  ensure_tdeepequals(
      "result matches expected",
      result,
      {
        {
          id = "alpha:beta";
          name = "gamma";
        };
        {
          id = "delta";
          {
            42;
            { data = true };
          }
        };
        {
          id = "delta";
          { id = "alpha"; 1; };
        };
      }
    )
end)

--------------------------------------------------------------------------------

-- TODO: Test that it fails correctly at index, call

test "unm-only-fsm" (function()
  local unm_called = false
  local expected_t = nil

  local fsm =
  {
    id = "unm";

    init =
    {
      "-unm";

      handler = function()
        ensure_equals("expected_t is not set", expected_t, nil)
        expected_t = { }
        return expected_t
      end
    };

    states =
    {
      ["-unm"] =
      {
        type = "unm"; id = "-unm";

        handler = function(self, t)
          ensure("expected_t is set", expected_t)
          ensure_equals("t is expected", t, expected_t)
          unm_called = true
          return 42
        end;
      };
    };
  }

  local dsl_manager = ensure("manager created", make_dsl_manager(fsm))
  local proxy = ensure("proxy created", dsl_manager:proxy("one"))
  ensure("unm handler not called", not unm_called)
  ensure_equals("unm returns expected value", -proxy, 42)
  ensure("unm handler called", unm_called)

  ensure_tdeepequals("finalize manager", dsl_manager:finalize(), { })
end)

--------------------------------------------------------------------------------

test "unm-fsm-updater" (function()

  local fsm =
  {
    id = "unm";

    init =
    {
      "unm:call";
      "-unm";

      handler = function(self)
        return { log = "{" }
      end;
    };

    states =
    {
      [false] =
      {
        type = "final", id = false;

        handler = function(self, t)
          t.log = t.log .. "}"
        end;
      };

      ["unm:call"] =
      {
        type = "call", id = "unm:call";

        "unm:call";
        false;

        handler = function(self, t, v)
          t.log = t.log .. "call("
            .. (is_table(v) and v.log or tostring(v)) .. ");"
        end;
      };

      ["-unm"] =
      {
        type = "unm", id = "-unm";

        handler = function(self, t)
          t.log = t.log .. "-unm;" -- TODO: Check this too somehow?

          return self
        end;
      };
    };
  }

  local dsl_manager = ensure("manager created", make_dsl_manager(fsm))
  do
    local proxy = ensure("proxy created", dsl_manager:proxy("one"))
    local helper = ensure("unm", -proxy)
    ensure("helper is not proxy", helper ~= proxy)

    ensure(
        "add state foo",
        helper:add_states(
            {
              {
                from = { "unm:call" };
                from_init = true;

                type = "index", id = "unm:foo";

                "unm:call";
                false;

                value = "foo";

                handler = function(self, t, k)
                  t.log = t.log .. "foo;"
                end
              };
            }
          )
      )
  end

  local proxy = ensure("proxy created", dsl_manager:proxy("two"))
  local result = proxy.foo(42).foo

  ensure("finalize manager", dsl_manager:finalize())

  ensure_tdeepequals(
      "result matches expected",
      result,
      {
        log = "{"
           .. "foo;"
           .. "call(42);"
           .. "foo;"
           .. "}"
            ;
      }
    )
end)

--------------------------------------------------------------------------------

-- TODO: Support multiple call exit states via predicates?
-- TODO: Improve error-reporting! It should be friendlier to scripters.
-- TODO: Test that isolated state-loops are caught by validation.

-- TODO: Support sealing for bootstrap (needs manager-level support to
--       keep state between proxy lifetimes?)
--       Sealing should disable unm, that's all?

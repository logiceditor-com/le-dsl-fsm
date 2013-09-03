--------------------------------------------------------------------------------
-- dsl-fsm/common_env.lua: DSL FSM common environment implementation
-- This file is a part of le-dsl-fsm project
-- Copyright (c) LogicEditor <info@logiceditor.com>
-- Copyright (c) le-dsl-fsm authors
-- See file `COPYRIGHT` for the license.
--------------------------------------------------------------------------------

local assert, error, getmetatable, setmetatable, tostring
    = assert, error, getmetatable, setmetatable, tostring

local table_remove = table.remove

--------------------------------------------------------------------------------

local check_dsl_fsm_handler_chunk
      = import 'dsl-fsm/check.lua'
      {
        'check_dsl_fsm_handler_chunk'
      }

local make_dsl_manager
      = import 'dsl-fsm/dsl_manager.lua'
      {
        'make_dsl_manager'
      }

local arguments
      = import 'lua-nucleo/args.lua'
      {
        'arguments'
      }

local make_checker
      = import 'lua-nucleo/checker.lua'
      {
        'make_checker'
      }

local capture_source_location
      = import 'lua-nucleo/diagnostics.lua'
      {
        'capture_source_location'
      }

local do_in_environment
      = import 'lua-nucleo/sandbox.lua'
      {
        'do_in_environment'
      }

local empty_table,
      tclone,
      tijoin_many
      = import 'lua-nucleo/table-utils.lua'
      {
        'empty_table',
        'tclone',
        'tijoin_many'
      }

local is_function,
      is_string,
      is_table
      = import 'lua-nucleo/type.lua'
      {
        'is_function',
        'is_string',
        'is_table'
      }

local assert_is_function
      = import 'lua-nucleo/typeassert.lua'
      {
        'assert_is_function'
      }

--------------------------------------------------------------------------------

local allow_any_dsl_namespace = setmetatable(
    { },
    {
      __index = function() return true end;
    }
  )

local create_dsl_env_mt
do
  -- A private method
  local create_meta_dsl_manager_proxy = function(self, target_helper)
    -- TODO: Test for "infinite" chains of -(-(meta)).
    local proxy = self.meta_dsl_manager_:proxy(
        "(-dsl)", -- TODO: ?!
        capture_source_location(5), -- TODO: ?! Tune error level!
        self.context_
      )
    self.context_.dsl_env_targets[proxy] = target_helper -- Yuck.

    return proxy
  end

  local dsl_fsm_unm_handler = function(helper, t)
    return create_meta_dsl_manager_proxy(
        assert(helper:context().dsl_env),
        helper
      )
  end

  local create_empty_dsl_fsm = function(id)

    return
    {
      id = id;

      init =
      {
        "-" .. id;
      };

      states =
      {
        ["-" .. id] =
        {
          type = "unm"; id = "-" .. id;

          handler = dsl_fsm_unm_handler;
        };
      };
    }
  end

  -- A private method
  -- Important: Namespace must be unique. Otherwise meta_finalizers will break.
  local get_dsl_manager = function(self, namespace)
    if namespace == "(-dsl)" then -- TODO: ?!
      return self.meta_dsl_manager_
    end

    local mgr = self.dsl_managers_[namespace]
    if mgr == nil then
      mgr = make_dsl_manager(
          create_empty_dsl_fsm(namespace),
          self.checker_
        )
      self.dsl_managers_[namespace] = mgr
      self.dsl_managers_order_[#self.dsl_managers_order_ + 1] = mgr
    end

    return mgr
  end

  local mt_index = function(t, k)
    local self = getmetatable(t)

    -- Note: Not using checker here, results will probably be too broken
    --       and mysterious if we'd allow DSL chunk execution to continue.
    if not is_string(k) or not self.allowed_namespaces_set_[k] then
      error(
            "attempted to access illegal DSL namespace `"
         .. (tostring(k) or "(?)") .. "'",
            2
        )
    end

    -- TODO: Do we need a better error reporting here?

    -- Intentionally not caching, proxies are not reusable.

    return assert(
        get_dsl_manager(self, k):proxy(
            k,
            capture_source_location(2),
            self.context_
          )
      )
  end

  local mt_newindex = function(t, k, v)
    -- Note: Not using checker here, results will probably be too broken
    --       and mysterious if we'd allow DSL chunk execution to continue.
    error(
          "attempted to write to a DSL construct `"
       .. (tostring(k) or "(?)") .. "'",
          2
      )
  end

  local fail = function(self, ...)
    return self.checker_:fail(...)
  end

  local ensure = function(self, ...)
    return self.checker_:ensure(...)
  end

  local good = function(self)
    return self.checker_:good()
  end

  local finalize = function(self)
    local res, err = self.checker_:result()
    if not res then
      return nil, err
    end

    -- Note that results from meta manager are ignored
    -- (except for errors, which are checked by checker)
    self.meta_dsl_manager_:finalize()
    local res, err = self.checker_:result()
    if not res then
      return nil, err
    end

    local results = { }

    for i = 1, #self.dsl_managers_order_ do
      tijoin_many(results, (self.dsl_managers_order_[i]:finalize()))
    end

    local res, err = self.checker_:result()
    if not res then
      return nil, err
    end

    return results
  end

  local dsl_fsm_final_state =
  {
    type = "final"; id = false;

    handler = function(self, t)
      -- TODO: Move this per-namespace context stuff to the core functionality?
      if not self:context().meta_finalizers then
        return t
      end

      local finalizers = self:context().meta_finalizers[self:namespace()]
      if not finalizers then
        return t
      end

      for i = 1, #finalizers do
        local new_t = finalizers[i].handler(self, t)
        if new_t ~= nil then
          t = new_t
        end
      end

      return t
    end;
  }

  local meta_dsl_fsm =
  {
    id = "(-dsl)";

    init =
    {
      "(-dsl)._add_states";
      "(-(-dsl))";
    };

    states =
    {
      [false] = dsl_fsm_final_state;

      ["(-dsl)._add_states"] =
      {
        type = "index", id = "(-dsl)._add_states";

        "(-dsl):_add_states(state_list)";

        value = "_add_states";
      };

      ["(-dsl):_add_states(state_list)"] =
      {
        type = "call", id = "(-dsl):_add_states(state_list)";

        "(-dsl)._add_states";
        false;

        handler = function(self, t, state_list)
          self:ensure_field_call(state_list)

          self:ensure_is("state_list", state_list, "table")

          if self:good() then
            self:ensure(
                "must have at least one state in the list",
                #state_list > 0
              )
          end

          local need_final_state = false

          local states_to_remove = { }
          local finalizers_to_add = { }

          if self:good() then
            for i = 1, #state_list do
              local state = state_list[i]

              -- TODO: Remove concatenation in ensure messages here and below.

              self:ensure_is("state " .. i, state, "table")

              if self:good() then
                local pfx = "state #" .. i .. " `"
                  .. (tostring(state.id or "(?)") or "(??)")
                  .. "' ."

                state.from = is_table(state.from)
                  and state.from
                   or { state.from }
                state.from_init = state.from_init or false

                self:ensure_is(pfx .. "from", state.from, "table")
                self:ensure_is(pfx .. "from_init", state.from_init, "boolean")

                if state.id == false or state.handler ~= nil then
                  self:ensure_is(pfx .. "handler", state.handler, "function")
                end

                self:ensure_is(pfx .. "type", state.type, "string")

                if state.id ~= false then
                  self:ensure_is(pfx .. "id", state.id, "string")
                end
              end

              if self:good() then
                -- TODO: Check better?
                if state.id == false then
                  need_final_state = true
                  -- TODO: Improve error reporting by providing more details
                  --       in the chunk name.
                  check_dsl_fsm_handler_chunk(self, "finalizer", state.handler)

                  if self:good() then
                    finalizers_to_add[#finalizers_to_add + 1] = state
                    states_to_remove[#states_to_remove + 1] = i
                  end
                end

                for i = 1, #state.from do
                  if state.from[i] == false then
                    need_final_state = true
                  end
                end

                for i = 1, #state do
                  if state[i] == false then
                    need_final_state = true
                  end
                end
              end
            end
          end

          if self:good() then
            for i = #states_to_remove, 1, -1 do
              table_remove(state_list, states_to_remove[i])
            end
          end

          -- Note: relying on underlying code to do further validation.

          if self:good() then
            local target = assert(self:context().dsl_env_targets[self:proxy()])

            if
              need_final_state and
              not target:have_state(false)
            then
              state_list[#state_list + 1] = dsl_fsm_final_state
            end

            local meta_finalizers = target:context().meta_finalizers
            if meta_finalizers == nil then
              meta_finalizers = { }
              target:context().meta_finalizers = meta_finalizers
            end

            local finalizers = meta_finalizers[target:namespace()]
            if finalizers == nil then
              finalizers = { }
              meta_finalizers[target:namespace()] = finalizers
            end

            for i = 1, #finalizers_to_add do
              finalizers[#finalizers + 1] = finalizers_to_add[i]
            end

            self:ensure(
                "add state list",
                target:add_states(state_list)
              )
          end

          if not self:good() then
            -- We're most likely too broken to continue.
            local res, err = self:context().dsl_env:result()
            error(err, 2) -- TODO: Tune level
          end
        end;
      };

      ["(-(-dsl))"] =
      {
        type = "unm"; id = "(-(-dsl))";

        handler = dsl_fsm_unm_handler;
      };
    };
  }

  local result = function(self)
    return self.checker_:result()
  end

  local dsl_env_targets_mt =
  {
    __mode = "k";
  }

  create_dsl_env_mt = function(allowed_namespaces_set, extra_context)
    extra_context = extra_context or empty_table

    arguments(
        "table", allowed_namespaces_set,
        "table", extra_context
      )

    local checker = make_checker()

    local context =
    {
      dsl_env_targets = setmetatable({ }, dsl_env_targets_mt);
      dsl_env = nil; -- Set below.
    }

    local self =
    {
      __index = mt_index;
      __newindex = mt_newindex;
      --
      ensure = ensure;
      fail = fail;
      --
      good = good;
      result = result;
      finalize = finalize;
      --
      allowed_namespaces_set_ = allowed_namespaces_set;
      checker_ = checker;
      dsl_managers_ = { };
      dsl_managers_order_ = { };
      meta_dsl_manager_ = assert(
          make_dsl_manager(tclone(meta_dsl_fsm), checker)
        );
      context_ = context;
    }

    context.dsl_env = self -- ?! Ugly.

    for k, v in pairs(extra_context) do
      if context[k] ~= nil then
        -- TODO: Hide "system" context keys.
        error("can't override system context key `" .. tostring(k) .. "'", 2)
      end
      context[k] = v
    end

    return self
  end
end

-- TODO: Support non-bootstrap version without meta?
--       (Or, at least, support sealing to disable meta.)
local do_in_common_dsl_environment = function(
    dsl_chunks,
    env,
    dsl_env_mt
  )
  if is_function(dsl_chunks) then
    dsl_chunks = { dsl_chunks }
  end

  env = env or { }
  dsl_env_mt = dsl_env_mt or create_dsl_env_mt(allow_any_dsl_namespace)

  arguments(
      "table", dsl_chunks,
      "table", env,
      "table", dsl_env_mt
    )

  setmetatable(env, dsl_env_mt)

  for i = 1, #dsl_chunks do
    dsl_env_mt:ensure(
        "run dsl chunk",
        do_in_environment(assert_is_function(dsl_chunks[i]), env)
      )

    if not dsl_env_mt:good() then
      break -- Stop execution before things get too weird.
    end
  end

  return dsl_env_mt:finalize()
end

--------------------------------------------------------------------------------

return
{
  allow_any_dsl_namespace = allow_any_dsl_namespace;
  create_dsl_env_mt = create_dsl_env_mt;
  do_in_common_dsl_environment = do_in_common_dsl_environment;
}

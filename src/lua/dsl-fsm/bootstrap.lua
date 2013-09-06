--------------------------------------------------------------------------------
-- dsl-fsm/bootstrap.lua: DSL FSM bootstrap code
-- This file is a part of le-dsl-fsm project
-- Copyright (c) LogicEditor <info@logiceditor.com>
-- Copyright (c) le-dsl-fsm authors
-- See file `COPYRIGHT` for the license.
--------------------------------------------------------------------------------

local unpack, error
    = unpack, error

--------------------------------------------------------------------------------

local is_string,
      is_table
      = import 'lua-nucleo/type.lua'
      {
        'is_string',
        'is_table'
      }

local timap,
      tset
      = import 'lua-nucleo/table-utils.lua'
      {
        'timap',
        'tset'
      }

local check_dsl_fsm_handler_chunk
      = import 'dsl-fsm/check.lua'
      {
        'check_dsl_fsm_handler_chunk'
      }

--------------------------------------------------------------------------------

local dsl_fsm_bootstrap_chunk = function()
  -- TODO: Try to eliminate more copy-paste an boilerplate code.

  local check_common_state_param = function(self, param)
    if self:good() then
      -- Preliminary format validation to improve
      -- error handling user-friendliness.
      -- (It is not very convenient to see errors at apply() time.)

      if is_string(param.from) then
        param.from = { param.from }
      end

      if param.from_init ~= nil then
        self:ensure_is("from_init", param.from_init, "boolean")
      end

      if param.from ~= nil then
        self:ensure_is("from", param.from, "table")

        if self:good() then
          self:ensure("from can't be empty", #param.from > 0)
        end
      else
        self:ensure(
            "must be from_init if no from specified",
            param.from_init == true
          )
      end

      self:ensure(
          "must have ins",
          param.from ~= nil or param.from_init ~= nil
        )

      if self:good() then
        self:ensure("must have outs", #param > 0)
      end

      if param.handler ~= nil then
        self:ensure_is("handler", param.handler, "function")
        if self:good() then
          -- TODO: Improve error reporting by providing more details
          --       in the chunk name.
          check_dsl_fsm_handler_chunk(
              self,
              "handler",
              param.handler
            )
        end
      end

      if param.meta_handler ~= nil then
        self:ensure_is("meta_handler", param.meta_handler, "function")
        if self:good() then
          -- TODO: Improve error reporting by providing more details
          --       in the chunk name.
          check_dsl_fsm_handler_chunk(
              self,
              "meta_handler",
              param.meta_handler
            )
        end
      end

      self:ensure_is("id", param.id, "string")
    end
  end

  local common_extension_states = function(states, param)
    local name = param.name
    local call_handler = param.call_handler
    local call_meta_handler = param.call_meta_handler
    local apply_to_id = param.apply_to_id or "(-dsl).<ext*>.apply_to"

    local outs = param.outs

    states[#states + 1] =
    {
      type = "index"; id = "(-dsl)." .. name;
      from_init = true;

      "(-dsl)." .. name .. "{param}";

      value = name;

      handler = function(self, t, k)
        t.states = t.states or { }
      end;
    }

    states[#states + 1] =
    {
      type = "call"; id = "(-dsl)." .. name .. "{param}";
      from = "(-dsl)." .. name;

      meta_handler = call_meta_handler; -- may be nil
      handler = call_handler;

      -- Must be last ones
      apply_to_id;
      unpack(outs);
    }

    return states
  end

  local state_param_checker = function(have_value_field, prepare_states)
    return function(self, t, param)
      self:ensure_field_call(param)
      self:ensure_is("param", param, "table")

      check_common_state_param(self, param)

      if have_value_field and self:good() then
        -- TODO: Allow arbitrary key types?
        self:ensure_is("value", param.value, "string")
      end

      if self:good() then
        prepare_states(self, t, param)
        return t
      end

      -- Pity user and simplify error handing by failing early.
      local res, err = self:context().dsl_env:result()
      error("broken meta DSL: " .. err, 2) -- TODO: Tune level
    end
  end

  local default_apply_to_handler = function(self, t, meta_dsl_proxy, _)
    -- Note that we can't reliably check for a field call,
    -- since meta_dsl_proxy can be our own proxy.
    -- We're checking for a single argument instead.
    self:ensure_is("single argument only", _, "nil")
    self:ensure_is("meta_dsl_proxy", meta_dsl_proxy, "table")

    if self:good() then
      meta_dsl_proxy._add_states(t.states)
    end

    if not self:good() then
      -- Too broken to continue.
      local res, err = self:context().dsl_env:result()
      error("broken meta DSL: " .. err, 2) -- TODO: Tune level
    end
  end

  local common_apply_to_states = function(states, param)
    local name = param.name or "<ext*>"
    local meta_handler = param.meta_handler or default_apply_to_handler

    states[#states + 1] =
    {
      type = "index"; id = "(-dsl)." .. name .. ".apply_to";
      from = "(-dsl)." .. name .. ".apply_to(meta_dsl_proxy)";

      "(-dsl)." .. name .. ".apply_to(meta_dsl_proxy)";

      value = "apply_to";
    }

    states[#states + 1] =
    {
      type = "call";
      id = "(-dsl)." .. name .. ".apply_to(meta_dsl_proxy)";
      from = "(-dsl)." .. name .. ".apply_to";

      "(-dsl)." .. name .. ".apply_to";
      false;

      meta_handler = meta_handler;
    }
  end

  local outs =
  {
    "(-dsl)._index";
    "(-dsl)._call";
    "(-dsl)._field_call";
    "(-dsl)._method_call";
    -- Added below:
    -- (-dsl)._final;
  }

  local extension_states = { }

  common_apply_to_states(extension_states, { })

  -- (-dsl)._index { param } .apply_to(meta_dsl_proxy)
  common_extension_states(
      extension_states,
      {
        outs = outs;
        name = "_index";
        call_handler = state_param_checker(
            true,
            function(self, t, param)
              if self:good() then
                param.type = "index"
                t.states[#t.states + 1] = param
              end
            end
          );
      }
    )

  -- (-dsl)._call { param } .apply_to(meta_dsl_proxy)
  common_extension_states(
      extension_states,
      {
        outs = outs;
        name = "_call";
        call_handler = state_param_checker(
            false,
            function(self, t, param)
              if self:good() then
                param.type = "call"
                t.states[#t.states + 1] = param
              end
            end
          );
      }
    )

  -- (-dsl)._field_call { param } .apply_to(meta_dsl_proxy)
  common_extension_states(
      extension_states,
      {
        outs = outs;
        name = "_field_call";
        -- TODO: Generalize copy-paste with _method_call below
        call_handler = state_param_checker(
            true,
            function(self, t, param)
              local handler = param.handler
              local meta_handler = param.meta_handler

              t.states[#t.states + 1] =
              {
                type = "index"; id = param.id;
                from = param.from;
                from_init = param.from_init;
                param.id .. "()";
                value = param.value;
              }

              local call_state =
              {
                type = "call"; id = param.id .. "()";
                from = param.id;

                meta_handler = meta_handler and function(self, t, ...)
                  self:ensure_field_call((...))
                  return meta_handler(self, t, ...)
                end or nil;

                handler = handler and function(self, t, ...)
                  self:ensure_field_call((...))
                  return handler(self, t, ...)
                end or nil;
              }

              for i = 1, #param do
                call_state[#call_state + 1] = param[i]
              end

              t.states[#t.states + 1] = call_state
            end
          );
      }
    )

  -- (-dsl)._method_call { param } .apply_to(meta_dsl_proxy)
  common_extension_states(
      extension_states,
      {
        outs = outs;
        name = "_method_call";
        -- TODO: Generalize copy-paste with _method_call below
        call_handler = state_param_checker(
            true,
            function(self, t, param)
              local handler = param.handler
              local meta_handler = param.meta_handler

              t.states[#t.states + 1] =
              {
                type = "index"; id = param.id;
                from = param.from;
                from_init = param.from_init;
                param.id .. "()";
                value = param.value;
              }

              local call_state =
              {
                type = "call"; id = param.id .. "()";
                from = param.id;

                meta_handler = meta_handler and function(self, t, ...)
                  self:ensure_method_call((...))
                  return meta_handler(self, t, ...)
                end or nil;

                handler = handler and function(self, t, ...)
                  self:ensure_method_call((...))
                  return handler(self, t, ...)
                end or nil;
              }

              for i = 1, #param do
                call_state[#call_state + 1] = param[i]
              end

              t.states[#t.states + 1] = call_state
            end
          );
      }
    )

  -- (-dsl)._extension { ext_list } .apply_to(meta_dsl_proxy)
  common_extension_states(
      extension_states,
      {
        outs = { };
        name = "_extension";
        apply_to_id = "(-dsl)._extension{param}*.apply_to";
        call_meta_handler = function(self, t, ext_list)
          -- TODO: validate ext_list somehow?
          self:ensure_field_call(ext_list)
          self:ensure_is("ext_list", ext_list, "table")

          if self:good() then
            t.states = ext_list
            return t
          end

          -- Pity user and simplify error handing by failing early.
          local res, err = self:context().dsl_env:result()
          error("broken meta DSL: " .. err, 2) -- TODO: Tune level
        end;
      }
    )

  common_apply_to_states(
      extension_states,
      {
        name = "_extension{param}*";
        meta_handler = function(self, t, meta_dsl_proxy, _)
          -- Note that we can't reliably check for a field call,
          -- since meta_dsl_proxy can be our own proxy.
          -- We're checking for a single argument instead.
          self:ensure_is("single argument only", _, "nil")
          self:ensure_is("meta_dsl_proxy", meta_dsl_proxy, "table")

          if self:good() then
            for i = 1, #t.states do
              t.states[i].apply_to(meta_dsl_proxy)
            end
          end

          if not self:good() then
            -- Too broken to continue.
            local res, err = self:context().dsl_env:result()
            error("broken meta DSL: " .. err, 2) -- TODO: Tune level
          end
        end;
      }
    )

  ;(-(-_))._add_states(extension_states)

  ;(-(-_))._field_call
  {
    id = "(-dsl)._extend";
    from_init = true;

    "(-dsl)._add_states";
    "(-dsl)._extend";
    false;

    value = "_extend";

    meta_handler = function(self, t, extensions)
      self:ensure_is("extensions", extensions, "table")

      return t, function()
        if self:good() then
          local proxy = self:proxy()
          for i = 1, #extensions do
            extensions[i].apply_to(proxy)
          end
        end

        if not self:good() then
          -- Too broken to continue.
          local res, err = self:context().dsl_env:result()
          error("broken meta DSL: " .. err, 2) -- TODO: Tune level
        end
      end
    end;
  }.apply_to(-(-_))

  ;(-(-_))._extend
  {
    -- (-dsl)._final { param } .apply_to(meta_dsl_proxy)
    (-(-_))._field_call
    {
      id = "(-dsl)._final";
      from_init = true;
      -- TODO: Lazy.
      from = timap(function(out) return out .. "{param}" end, outs);

      value = "_final";

      meta_handler = function(self, t, param)
        self:ensure_is("extensions", param, "table")

        if is_string(param.from) then
          param.from = { param.from }
        end
        self:ensure_is("from", param.from, "table")
        if self:good() then
          for i = 1, #param.from do
            self:ensure_is("from[" .. i .. "]", param.from[i], "string")
          end
        end

        self:ensure_is("handler", param.handler, "function")
        if self:good() then
          -- TODO: Improve error reporting by providing more details
          --       in the chunk name.
          check_dsl_fsm_handler_chunk(
              self,
              "handler",
              param.handler
            )
        end

        if self:good() then
          param.from = tset(param.from)

          t.states[#t.states + 1] =
          {
            type = "final"; id = false;

            -- TODO: Avoid creating closure here.
            handler = function(self, t)
              if param.from[self:prev_state_id()] then
                return param.handler(self, t)
              end

              return t
            end;
          }
        end
      end;

      "(-dsl).<ext*>.apply_to";
      "(-dsl)._final";
      unpack(outs); -- Should be the last one.
    }
    ;
  }
end

--------------------------------------------------------------------------------

return
{
  dsl_fsm_bootstrap_chunk = dsl_fsm_bootstrap_chunk;
}

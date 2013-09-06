--------------------------------------------------------------------------------
-- dsl-fsm/dsl_manager.lua: DSL FSM manager
-- This file is a part of le-dsl-fsm project
-- Copyright (c) LogicEditor <info@logiceditor.com>
-- Copyright (c) le-dsl-fsm authors
-- See file `COPYRIGHT` for the license.
--------------------------------------------------------------------------------

local assert, error, getmetatable, pairs, select, setmetatable, tostring, type
    = assert, error, getmetatable, pairs, select, setmetatable, tostring, type

local table_concat
    = table.concat

local debug_traceback
    = debug.traceback

--------------------------------------------------------------------------------

require 'lua-nucleo'

--------------------------------------------------------------------------------

local arguments,
      optional_arguments,
      method_arguments
      = import 'lua-nucleo/args.lua'
      {
        'arguments',
        'optional_arguments',
        'method_arguments'
      }

local is_function,
      is_number,
      is_table
      = import 'lua-nucleo/type.lua'
      {
        'is_function',
        'is_number',
        'is_table'
      }

local assert_is_table
      = import 'lua-nucleo/typeassert.lua'
      {
        'assert_is_table'
      }

local tclone,
      tijoin_many,
      torderedset,
      torderedset_insert,
      torderedset_remove,
      toverride_many
      = import 'lua-nucleo/table-utils.lua'
      {
        'tclone',
        'tijoin_many',
        'torderedset',
        'torderedset_insert',
        'torderedset_remove',
        'toverride_many'
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

local check_dsl_fsm
      = import 'dsl-fsm/check.lua'
      {
        'check_dsl_fsm'
      }

--------------------------------------------------------------------------------

local make_dsl_manager
do
  local add_transition_impl = function(fsm, state_from, state_id_to)
    arguments(
        "table", fsm,
        "table", state_from
        -- "boolean|string", state_id_to
      )

    if not fsm.states[state_id_to] then
      return
        nil,
        "unknown destination state id `" .. tostring(state_id_to) .. "'"
    end

    for i = 1, #state_from do
      if state_from[i] == state_id_to then
        -- Transition already exists.
        -- Not failing to simplify bootstrapping code.
        return true
      end
    end

    state_from[#state_from + 1] = state_id_to

    return true
  end

  local add_states_impl = function(fsm, states)
    arguments(
        "table", fsm,
        "table", states
      )

    local new_state_ids = { }
    local state_froms = { }

    for i = 1, #states do
      local state = tclone(states[i])

      local state_id = state.id
      if fsm.states[state_id] or new_state_ids[state_id] then
        return
          nil,
          "fsm `" .. tostring(fsm.id) .. "' already has state with id `"
          .. tostring(state_id) .. "'"
      end

      new_state_ids[state_id] = true

      state_froms[state_id] = state.from
      state.from = nil

      fsm.states[state_id] = state

      if state.from_init then
        local res, err = add_transition_impl(fsm, fsm.init, state_id)
        if not res then
          return nil, err
        end
      end
    end

    for to_id, from_ids in pairs(state_froms) do
      for i = 1, #from_ids do
        local from = fsm.states[from_ids[i]]
        if not from then
          return
            nil,
            "fsm `" .. tostring(fsm.id) .. "': unknown source state id `"
            .. tostring(from_ids[i]) ..
            "' for state `" .. tostring(to_id) .. "'"
        end

        local res, err = add_transition_impl(fsm, from, to_id)
        if not res then
          return nil, err
        end
      end
    end

    return true
  end

  local add_states = function(self, states)
    method_arguments(
        self,
        "table", states
      )

    do
      local fsm = tclone(self.fsm_)

      local res, err = add_states_impl(fsm, states)
      if not res then
        return nil, err
      end

      local res, err = check_dsl_fsm(fsm)
      if not res then
        return nil, err
      end
    end

    assert(add_states_impl(self.fsm_, states))

    return true
  end

  local have_state = function(self, state_id)
    method_arguments(
        self
        -- "string|boolean", state_id
      )

    return not not self.fsm_.states[state_id]
  end

  local register_proxy = function(self, proxy)
    assert(self.active_proxies_[proxy] == nil, "double registration")
    torderedset_insert(self.active_proxies_, proxy)
  end

  local unregister_proxy = function(self, proxy)
    assert(self.active_proxies_[proxy] ~= nil, "double finalization")
    if not getmetatable(proxy):should_store_finalized_data() then
      torderedset_remove(self.active_proxies_, proxy)
    end
  end

  local proxy
  do
    local do_transition -- Forward declaration.

    local tidyup_proxy = function(self, proxy)
      assert(self.state_ == false)

      -- Assuming proxy is unregistered by do_transition
      setmetatable(proxy, nil)
      if is_table(self.data_) then
        -- Note that proxy is always empty table.
        toverride_many(proxy, self.data_)
      end

      local result = self.data_
      self.data_ = nil

      return result
    end

    -- Is not called if we arrive at a final state dynamically.
    local force_finalization = function(self, proxy)
      method_arguments(
          self,
          "table", proxy
        )

      -- TODO: Optimizable! Do lookup!
      --       (Note that there can be at most one final call state)
      for i = 1, #self.state_ do
        if self.fsm_.states[self.state_[i]].type == "final" then
          do_transition(self, self.state_[i], proxy)

          tidyup_proxy(self, proxy)

          return proxy
        end
      end

      self.helper_:fail(
          "unfinished dsl construct "
       .. "(can't be finalized in `"
       .. tostring(self.state_.id or "(init)") .. "' state)"
        )

      -- TODO: This likely will mess up foo:bar (baz:quo()) constructs.
      --       Note that one shouldn't return proxy here,
      --       or finalization will be attempted again,
      --       and intense error message spamming will likely ensue.
      return nil -- Tough luck.
    end

    local maybe_finalize_many
    do
      local function maybe_finalize(not_this_one, value, visited)
        visited = visited or { }

        if visited[value] then
          -- TODO: Is there a way to fail softer here?
          error("recursive table detected on finalization")
        end

        if value == not_this_one then
          return value -- Probably a method call, pass through
        end

        local self = is_table(value) and getmetatable(value)
        if self and self.force_finalization then -- Metatable duck typing.
          value = self:force_finalization(value)
        end

        if is_table(value) then
          visited[value] = true
          for k, v in pairs(value) do
            -- Intentionally not finalizing keys
            -- TODO: Warn user if there is a proxy in the keys?
            value[k] = maybe_finalize(nil, v, visited)
          end
          visited[value] = nil
        end

        return value
      end

      local function impl(not_this_one, n, a, ...)
        if n > 1 then
          return
            maybe_finalize(not_this_one, a),
            -- pass through potential method call self only as first argument
            impl(nil, n - 1, ...)
        end

        return maybe_finalize(not_this_one, a)
      end

      maybe_finalize_many = function(not_this_one, ...)
        return impl(not_this_one, select("#", ...), ...)
      end
    end

    do_transition = function(self, to_state_id, proxy, ...)

      self.prev_state_id_ = self.state_.id -- may be nil on init

      local transition = (self.state_.id or "(init)")
        .. "->" .. (to_state_id or "(final)")
      if self.in_transition_ then
        error(
            "can't do transition " .. transition
            .. ": already in transition " .. self.in_transition_
          )
      end

      self.in_transition_ = transition

      self.state_ = assert(self.fsm_.states[to_state_id])

      local new_data = nil
      local on_after_transition = nil

      -- TODO: final state should not support meta_handler.
      --       fix here and in checker.
      if self.state_.meta_handler then
        -- TODO: In theory, __call may return multiple values.
        --       Should we support this?
        new_data, on_after_transition = self.state_.meta_handler(
            self.helper_, self.data_, ... -- No finalization
          )

        if new_data ~= nil then
          self.data_ = new_data
        end
      end

      if self.state_.handler then
        -- TODO: In theory, __call may return multiple values.
        --       Should we support this?
        new_data = self.state_.handler(
            self.helper_, self.data_, maybe_finalize_many(proxy, ...)
          )

        if new_data ~= nil then
          self.data_ = new_data
        end
      end

      self.in_transition_ = false -- This is relevant to handler calls only.

      if on_after_transition then
        on_after_transition()
      end

      if self.state_.id == false then -- final state
        unregister_proxy(self.manager_, proxy)

        self.state_ = false -- No more transitions possible

        return tidyup_proxy(self, proxy)
      end

      if self.state_.type == "unm" then -- unm state is final too
        unregister_proxy(self.manager_, proxy)

        self.state_ = false -- No more transitions possible

        return tidyup_proxy(self, proxy)
      end

      -- Auto-transition to final state if it is the only choice
      -- Note that we intentionally not doing auto-transition to an unm state.
      if #self.state_ == 1 and self.state_[1] == false then
        return do_transition(self, false, proxy)
      end

      return proxy
    end

    local mt_index = function(t, k)
      local self = getmetatable(t)
      assert(
          self.state_,
          "bad impl: arrived at final state without finalization (index)"
        )

      -- TODO: Optimizable! Lookup key!
      for i = 1, #self.state_ do
        local state = self.fsm_.states[self.state_[i]]
        if state.type == "index" then
          local match = self.fsm_.states[self.state_[i]].value
          if k == match or is_function(match) and match(self, t, k) then
            return do_transition(self, self.state_[i], t, k)
          end
        end
      end

      -- Transition not found, fail.

      local expected_states = { }
      for i = 1, #self.state_ do
        expected_states[#expected_states + 1] = self.state_[i] or "(final)"
      end

      self.helper_:fail(
          debug_traceback(
              "unexpected index state transition attempt from `"
           .. (self.state_.id or "(init)") .. "', by index `"
           .. tostring(k) .. "'," .. " expected one of { "
           .. table_concat(expected_states, " | ") .. " }",
              2
            )
        )

      return t
    end

    local mt_call = function(t, ...)
      local self = getmetatable(t)
      assert(
          self.state_,
          "bad impl: arrived at final state after finalization (call)"
        )

      -- TODO: Optimizable! Do lookup!
      --       (Note that there can be at most one outgoing call state)
      for i = 1, #self.state_ do
        if self.fsm_.states[self.state_[i]].type == "call" then
          return do_transition(self, self.state_[i], t, ...)
        end
      end

      -- Transition not found, fail.

      local expected_states = { }
      for i = 1, #self.state_ do
        expected_states[#expected_states + 1] = self.state_[i] or "(final)"
      end

      self.helper_:fail(
          debug_traceback(
              "unexpected call state transition attempt from `"
           .. (self.state_.id or "(init)") .. "',"
           .. " expected one of { " .. table_concat(expected_states, " | ")
           .. " }",
              2
            )
        )

      return t
    end

    local mt_newindex = function(t, k, v)
      -- TODO: Add a state type to handle that?
      error("can't write to read-only object", 2)
    end

    local mt_unm = function(t)
      local self = getmetatable(t)
      assert(
          self.state_,
          "bad impl: arrived at unm state after finalization (unm)"
        )

      -- TODO: Optimizable! Lookup key!
      for i = 1, #self.state_ do
        local state = self.fsm_.states[self.state_[i]]
        if state.type == "unm" then
          return do_transition(self, self.state_[i], t)
        end
      end

      -- Transition not found, fail.

      local expected_states = { }
      for i = 1, #self.state_ do
        expected_states[#expected_states + 1] = self.state_[i] or "(unm)"
      end

      self.helper_:fail(
          debug_traceback(
              "unexpected unm state transition attempt from `"
           .. (self.state_.id or "(init)") .. "',"
           .. " expected one of { " .. table_concat(expected_states, " | ")
           .. " }",
              2
            )
        )

      return t
    end

    local wrap_helper_object
    do
      -- TODO: Simplify

      local make_helper_wrapper
      do
        local mt_tostring = function(t)
          return t.at.file .. ":" .. t.at.line .. ": " .. t.msg
        end

        local mt_concat = function(lhs, rhs)
          return tostring(lhs) .. tostring(rhs)
        end

        local delegate = function(method)

          return function(self, ...)
            return self.dsl_manager_[method](
                self.dsl_manager_,
                ...
              )
          end
        end

        local delegate_with_msg = function(method)

          return function(self, msg, ...)
            self.smart_msg_.msg = msg -- Hack.
            return self.dsl_manager_[method](
                self.dsl_manager_,
                self.smart_msg_,
                ...
              )
          end
        end

        local add_states = delegate("add_states")
        local have_state = delegate("have_state")

        local fail = delegate_with_msg("fail")
        local ensure = delegate_with_msg("ensure")
        local ensure_is = delegate_with_msg("ensure_is")

        local ensure_method_call = function(self, t)
          return self:ensure("method call required", self:is_self(t))
        end

        local ensure_field_call = function(self, t)
          return self:ensure("field call required", not self:is_self(t))
        end

        local good = delegate("good")

        local is_self = function(self, t)
          return t == self.proxy_
        end

        local eat_self = function(self, t, ...)
          if self:is_self(t) then
            return ...
          end
          return t, ...
        end

        local namespace = function(self)
          return self.namespace_
        end

        local context = function(self)
          return self.context_
        end

        local proxy = function(self)
          return self.proxy_
        end

        local store_finalized_data = function(self)
          getmetatable(self.proxy_):store_finalized_data()
        end

        local prev_state_id = function(self)
          return getmetatable(self.proxy_):prev_state_id()
        end

        make_helper_wrapper = function(
            dsl_manager, namespace_name, proxy_object, at, context_data
          )

          return
          {
            is_self = is_self;
            eat_self = eat_self;
            namespace = namespace;
            prev_state_id = prev_state_id;
            --
            fail = fail;
            ensure = ensure;
            ensure_is = ensure_is;
            ensure_method_call = ensure_method_call;
            ensure_field_call = ensure_field_call;
            good = good;
            --
            add_states = add_states;
            have_state = have_state;
            --
            context = context;
            proxy = proxy; -- Yuck!
            --
            store_finalized_data = store_finalized_data;
            --
            namespace_ = namespace_name;
            proxy_ = proxy_object; -- Yuck.
            dsl_manager_ = dsl_manager;
            smart_msg_ = setmetatable(
                {
                  at = at;
                  msg = nil;
                },
                {
                  __tostring = mt_tostring;
                  __concat = mt_concat;
                }
              );
            context_ = context_data;
          }
        end
      end

      wrap_helper_object = function(
          self, namespace_name, helper, proxy, at, context
        )
        method_arguments(
            self,
            "string", namespace_name,
            "table", helper,
            "table", proxy,
            "table", at
            -- "*", context
          )

        assert(getmetatable(helper) == nil)

        return setmetatable(
            helper,
            {
              __index = make_helper_wrapper(
                  self, namespace_name, proxy, at, context
                );
            }
          )
      end
    end

    -- TODO: Bad naming. Make more distiguishable from "should_...()"
    local store_finalized_data = function(self)
      method_arguments(self)
      self.store_finalized_data_ = true
    end

    local should_store_finalized_data = function(self)
      method_arguments(self)
      return self.store_finalized_data_
    end

    local prev_state_id = function(self)
      method_arguments(self)
      return self.prev_state_id_
    end

    proxy = function(self, namespace_name, at, context)
      if at == nil then
        at = 2
      end
      if is_number(at) then
        at = capture_source_location(at)
      end
      method_arguments(
          self,
          "string", namespace_name,
          "table", at
          -- "*", context
        )

      local proxy = { }

      local helper = wrap_helper_object(
          self,
          namespace_name,
          self.fsm_.factory(),
          proxy,
          at,
          context
        )

      setmetatable(
          proxy,
          {
            force_finalization = force_finalization;
            prev_state_id = prev_state_id; -- Hack?
            --
            store_finalized_data = store_finalized_data;
            should_store_finalized_data = should_store_finalized_data;
            --
            __index = mt_index;
            __newindex = mt_newindex;
            __call = mt_call;
            __unm = mt_unm;
            --
            fsm_ = self.fsm_;
            helper_ = helper;
            state_ = assert(self.fsm_.init);
            data_ = assert_is_table(self.fsm_.init.handler(helper));
            manager_ = self; -- Ugly
            in_transition_ = false;
            store_finalized_data_ = false;
            prev_state_id_ = nil;
          }
        )

      register_proxy(self, proxy)

      return proxy
    end
  end

  local fail = function(self, msg)
    return self.checker_:fail(msg)
  end

  local ensure = function(self, msg, cond, ...)
    return self.checker_:ensure(msg, cond, ...)
  end

  local ensure_is = function(self, msg, value, expected_type)
    if type(value) ~= expected_type then
      self.checker_:fail(
          msg
          .. ": expected value type " .. tostring(expected_type)
          .. ", but got type " .. type(value)
        )
    end

    return value
  end

  local good = function(self)
    method_arguments(self)

    return self.checker_:good()
  end

  local finalize = function(self)
    method_arguments(self)

    -- Make a copy, since unregistration removes a proxy
    -- Note that we can't use tclone(), it removes metatables.
    local registry = { }
    for i = 1, #self.active_proxies_ do
      registry[i] = self.active_proxies_[i]
    end

    for i = #registry, 1, -1 do
      local mt = getmetatable(registry[i])
      if mt then -- May be already finalized
        registry[i] = mt:force_finalization(registry[i])
      end
    end

    if not self:good() then
      return self.checker_:result()
    end

    return registry
  end

  make_dsl_manager = function(fsm, checker)
    checker = checker or make_checker()

    arguments(
        "table", fsm,
        "table", checker
      )

    local res, err = check_dsl_fsm(fsm)
    if not res then
      return nil, err
    end

    return
    {
      proxy = proxy;
      --
      fail = fail;
      ensure = ensure;
      ensure_is = ensure_is;
      --
      add_states = add_states;
      have_state = have_state;
      --
      good = good;
      --
      finalize = finalize;
      --
      fsm_ = fsm;
      checker_ = checker;
      active_proxies_ = torderedset({ });
    }
  end
end

--------------------------------------------------------------------------------

return
{
  make_dsl_manager = make_dsl_manager;
}

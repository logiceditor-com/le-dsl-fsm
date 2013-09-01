--------------------------------------------------------------------------------
-- dsl-fsm/check.lua: DSL FSM validator
-- This file is a part of le-dsl-fsm project
-- Copyright (c) LogicEditor <info@logiceditor.com>
-- Copyright (c) le-dsl-fsm authors
-- See file `COPYRIGHT` for the license.
--------------------------------------------------------------------------------

local error, pairs, tostring, type
    = error, pairs, tostring, type

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
      is_string,
      is_table
      = import 'lua-nucleo/type.lua'
      {
        'is_function',
        'is_string',
        'is_table'
      }

local tisempty
      = import 'lua-nucleo/table-utils.lua'
      {
        'tisempty'
      }

local make_checker
      = import 'lua-nucleo/checker.lua'
      {
        'make_checker'
      }

local make_chunk_inspector
      = import 'lua-aplicado/chunk_inspector.lua'
      {
        'make_chunk_inspector'
      }

--------------------------------------------------------------------------------

local check_dsl_fsm_handler_chunk = function(checker, chunk_name, chunk)
  arguments(
      "table", checker,
      "string", chunk_name,
      "function", chunk
    )

  local ci = make_chunk_inspector(chunk)

  for name, locations in pairs(ci:list_gets()) do
    for i = 1, #locations do
      local location = locations[i]

      checker:fail(
          location.source .. ":" .. location.line
       .. ": bad " .. chunk_name
       .. ": reads from a global `" .. tostring(name) .. "'"
        )
    end
  end

  for name, locations in pairs(ci:list_sets()) do
    for i = 1, #locations do
      local location = locations[i]

      checker:fail(
          location.source .. ":" .. location.line
       .. ": bad " .. chunk_name
       .. ": writes to a global `" .. tostring(name) .. "'"
        )
    end
  end
end

local check_dsl_fsm
do
  -- TODO: Can we make unm into a non-final state and still be able to return
  --       arbitrary object? Do we want to?

  -- Intentionally not using old config_dsl for validation,
  -- it depends on old dsl stuff.

  local default_factory = function() return { } end
  local default_final_handler = function(self, t) return t end

  check_dsl_fsm = function(fsm)
    if not is_table(fsm) then
      return nil, "dsl fsm must be table, got " .. type(fsm)
    end

    local checker = make_checker()

    checker:ensure("bad fsm.id, must be string", is_string(fsm.id))

    if fsm.factory == nil then
      fsm.factory = default_factory
    end

    -- TODO: Remove concatenations from ensure messages!

    checker:ensure(
        "bad fsm `" .. tostring(fsm.id) .. "' factory, must be function or nil",
        is_function(fsm.factory)
      )

    checker:ensure(
        "bad fsm `" .. tostring(fsm.id) .. "' init, must be table",
        is_table(fsm.init)
      )
    checker:ensure(
        "bad fsm `" .. tostring(fsm.id) .. "' states, must be table",
         is_table(fsm.states)
      )

    if not checker:good() then
      -- No sense to check further, too broken.
      return checker:result()
    end

    local all_states = { }
    local accessible_states = { }
    local have_non_final_non_unm_states = false

    --
    -- fsm.factory
    --
    check_dsl_fsm_handler_chunk(
        checker, "fsm `" .. tostring(fsm.id) .. "' factory", fsm.factory
      )

    --
    -- fsm.states
    --
    checker:ensure(
        "bad fsm `" .. tostring(fsm.id) .. "': must have at least one state",
        not tisempty(fsm.states)
      )

    if fsm.states[false] == true then
      fsm.states[false] =
      {
        type = "final", id = false;

        handler = default_final_handler;
      }
    end

    for id, state in pairs(fsm.states) do
      all_states[#all_states + 1] = id

      if state.type ~= "final" and state.type ~= "unm" then
        have_non_final_non_unm_states = true
      end

      if state.type == "final" then
        checker:ensure(
            "bad fsm `" .. tostring(fsm.id)
            .. "': final state id must be false",
            id == false, tostring(id)
          )
      else
        checker:ensure(
            "bad fsm `" .. tostring(fsm.id) .. "' "
         .. (state.type == "unm" and "unm" or "transitional")
         .. " state id must be string",
            is_string(id), type(id)
          )
      end

      if
        state.type == "final" or
        state.type == "call" or
        state.type == "unm"
      then
        if is_function(state.handler) then
          check_dsl_fsm_handler_chunk(
              checker,
              "fsm `" .. tostring(fsm.id) .. "' states["
              .. tostring(id) .. "].handler",
              state.handler
            )
        elseif state.handler ~= nil then
          checker:fail(
              "bad fsm `" .. tostring(fsm.id) .. "' state `" .. tostring(id)
           .. "': handler must be function or nil"
            )
        end

        if is_function(state.meta_handler) then
          check_dsl_fsm_handler_chunk(
              checker,
              "fsm `" .. tostring(fsm.id) .. "' states["
              .. tostring(id) .. "].meta_handler",
              state.meta_handler
            )
        elseif state.meta_handler ~= nil then
          checker:fail(
              "bad fsm `" .. tostring(fsm.id) .. "' state `" .. tostring(id)
           .. "': meta_handler must be function or nil"
            )
        end

        if not state.handler and not state.meta_handler then
          checker:fail(
              "bad fsm `" .. tostring(fsm.id) .. "' state `" .. tostring(id)
           .. "': state type `" .. state.type
           .. "' requires handler or meta_handler function"
            )
        end
      elseif state.type == "index" then
        if is_function(state.handler) then
          check_dsl_fsm_handler_chunk(
              checker,
              "fsm `" .. tostring(fsm.id) .. "' states["
              .. tostring(id) .. "].handler",
              state.handler
            )
        elseif state.handler ~= nil then
          checker:fail(
              "bad fsm `" .. tostring(fsm.id) .. "' state `" .. tostring(id)
           .. "': handler must be function or nil"
            )
        end

        if is_function(state.meta_handler) then
          check_dsl_fsm_handler_chunk(
              checker,
              "fsm `" .. tostring(fsm.id) .. "' states["
              .. tostring(id) .. "].meta_handler",
              state.meta_handler
            )
        elseif state.meta_handler ~= nil then
          checker:fail(
              "bad fsm `" .. tostring(fsm.id) .. "' state `" .. tostring(id)
           .. "': meta_handler must be function or nil"
            )
        end

        -- TODO: allow numeric and boolean keys?
        if is_function(state.value) then
          check_dsl_fsm_handler_chunk(
              checker,
              "fsm `" .. tostring(fsm.id) .. "' states["
              .. tostring(id) .. "].value",
              state.value
            )
        elseif not is_string(state.value) then
          checker:fail(
              "bad fsm `" .. tostring(fsm.id) .. "' state `" .. tostring(id)
           .. "': index state must have `value' field that is string"
           .. " or function"
            )
        end
      else
        checker:fail(
            "bad fsm `" .. tostring(fsm.id) .. "': unknown state `"
         .. tostring(id) .. "' type `" .. tostring(state.type) .. "'"
          )
      end

      if state.id ~= id then
        checker:fail(
            "bad fsm `" .. tostring(fsm.id)
         .. "': unexpected state id field value `" .. tostring(state.id)
         .. "' for state id `" .. tostring(id) .. "'"
          )
      end

      if not (state.type == "final" or state.type == "unm") and #state < 1 then
        checker:fail(
            "bad fsm `" .. tostring(fsm.id)
         .. "': non-final state `" .. tostring(id)
         .. "' must have at least one exit state"
          )
      end

      local num_call_refs = 0
      local unm_id = false
      local index_values = { }

      for i = 1, #state do
        accessible_states[state[i]] = true

        local ref = fsm.states[state[i]]
        if not ref then
          checker:fail(
              "bad fsm `" .. tostring(fsm.id)
           .. "': missing definition of state #" .. i .. ": `"
           .. tostring(state[i]) .. "', referenced from state `"
           .. tostring(state.id) .. "'"
            )
        else
          if state.type == "index" or state.type == "call" then
            if ref.type == "call" then
              num_call_refs = num_call_refs + 1
              if num_call_refs > 1 then
                checker:fail(
                    "bad fsm `" .. tostring(fsm.id) .. "' state `"
                 .. tostring(state.id)
                 .. "' can reference at most one call state, found more (#"
                 .. i .. ", `" .. tostring(ref.id) .. "')"
                  )
              end
            end
          elseif state.type == "final" or state.type == "unm" then
            checker:fail(
                "bad fsm `" .. tostring(fsm.id) .. "': "
             .. state.type .. " call state `"
             .. tostring(state.id) .. "'"
             .. " can't reference any states, but references state id `"
             .. tostring(ref.id) .. "'"
              )
          else
            -- State type must be valid, because we've just checked it above.
            error(
                "bad implementation: forgot to support state type `"
             .. tostring(state.type) "'"
              )
          end

          if ref.type == "unm" then
            if unm_id == false then
              unm_id = ref.id
            else
              checker:fail(
                  "bad fsm `" .. tostring(fsm.id) .. "': "
               .. state.type .. " state `"
               .. tostring(state.id) .. "'"
               .. " can reference at most one unm state (tried to reference `"
               .. tostring(ref.id) .. "', but already referenced `"
               .. tostring(unm_id) .. "')"
                )
            end
          elseif ref.type == "index" then
            -- Note that function predicates are not caught here.
            if index_values[ref.value] == nil then
              index_values[ref.value] = ref.id
            else
              checker:fail(
                  "bad fsm `" .. tostring(fsm.id) .. "': "
               .. state.type .. " state `"
               .. tostring(state.id) .. "'"
               .. " contains more than one reference to value `"
               .. tostring(ref.value) .. "' (found `"
               .. tostring(ref.id) .. "', but already seen `"
               .. tostring(index_values[ref.value]) .. "')"
                )
            end
          end
        end

      end

    end

    --
    -- fsm.init
    --

    checker:ensure(
        "bad fsm `" .. tostring(fsm.id)
        .. "' init: must list at least one state transition",
        #fsm.init > 0
      )

    -- TODO: DRY with common state validation above.

    local num_call_refs = 0
    local unm_id = false
    local index_values = { }
    for i = 1, #fsm.init do
      accessible_states[fsm.init[i]] = true

      local ref = fsm.states[fsm.init[i]]
      if not ref then
        checker:fail(
            "bad fsm `" .. tostring(fsm.id)
         .. "' init: missing definition of initial state #" .. i .. ": `"
         .. tostring(fsm.init[i]) .. "'"
          )
      elseif ref.type == "call" then
        num_call_refs = num_call_refs + 1
        if num_call_refs > 1 then
          checker:fail(
              "bad fsm `" .. tostring(fsm.id) .. "' init:"
           .. " can reference at most one call state, found more (#"
           .. i .. ", `" .. tostring(ref.id) .. "')"
            )
        end
      elseif ref.type == "unm" then
        if unm_id == false then
          unm_id = ref.id
        else
          checker:fail(
              "bad fsm `" .. tostring(fsm.id) .. "' init:"
           .. " can reference at most one unm state (tried to reference `"
           .. tostring(ref.id) .. "', but already referenced `"
           .. tostring(unm_id) .. "')"
            )
        end
      elseif ref.type == "index" then
        -- Note that function predicates are not caught here.
        if index_values[ref.value] == nil then
          index_values[ref.value] = ref.id
        else
          checker:fail(
              "bad fsm `" .. tostring(fsm.id) .. "' init:"
           .. " contains more than one reference to value `"
           .. tostring(ref.value) .. "' (found `"
           .. tostring(ref.id) .. "', but already seen `"
           .. tostring(index_values[ref.value]) .. "')"
            )
        end
      end
    end

    if fsm.init.handler == nil then
      fsm.init.handler = function() return { } end
    end
    if not is_function(fsm.init.handler) then
      checker:fail(
          "bad fsm `" .. tostring(fsm.id)
       .. "' init.handler: must be function or nil, got "
       .. type(fsm.init.handler)
        )
    else
      check_dsl_fsm_handler_chunk(
          checker,
          "fsm `" .. tostring(fsm.id) .. "' init.handler",
          fsm.init.handler
        )
    end

    for i = 1, #all_states do
      if not accessible_states[all_states[i]] then
        if
          #all_states == 2 and
          all_states[i] == false and
          not have_non_final_non_unm_states
        then
          -- TODO: Hack for empty unm-only states. Fix that somehow.
          --       Allowing unaccessible final state if only unm state exists.
        else
          checker:fail(
              "bad fsm `" .. tostring(fsm.id) .. "': state `"
           .. tostring(all_states[i]) .. "' is inaccessible"
            )
        end
      end
    end

    return checker:result()
  end
end

--------------------------------------------------------------------------------

return
{
  check_dsl_fsm_handler_chunk = check_dsl_fsm_handler_chunk;
  check_dsl_fsm = check_dsl_fsm;
}

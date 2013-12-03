--------------------------------------------------------------------------------
-- dsl-fsm/util/path_mt.lua: Path-based DSL walker hook micro-language
-- This file is a part of le-dsl-fsm project
-- Copyright (c) LogicEditor <info@logiceditor.com>
-- Copyright (c) le-dsl-fsm authors
-- See file `COPYRIGHT` for the license.
--------------------------------------------------------------------------------

local assert, type, getmetatable, setmetatable, pairs
    = assert, type, getmetatable, setmetatable, pairs

--------------------------------------------------------------------------------

local arguments
      = import 'lua-nucleo/args.lua'
      {
        'arguments'
      }

local is_function,
      is_string
      = import 'lua-nucleo/type.lua'
      {
        'is_function',
        'is_string'
      }

local tset
      = import 'lua-nucleo/table-utils.lua'
      {
        'tset'
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

-- TODO: Move to lua-nucleo/table-utils.lua
--       https://redmine-tmp.iphonestudio.ru/issues/2961
local tireverse = function(t)
  local r = { }
  for i = #t, 1, -1 do
    r[#r + 1] = t[i]
  end
  return r
end

--------------------------------------------------------------------------------

local create_path_mt
do
  local match_path = function(reverse_tail, path)
    if #reverse_tail > #path then
      return false
    end

    for i = 1, #reverse_tail do
      local actual = path[#path - i + 1]
      local expected = reverse_tail[i]

      if is_function(expected) then
        if not expected(actual) then
          return false
        end
      elseif actual ~= expected then
        return false
      end
    end

    return true
  end

  local path_mt_dsl = function() --[[dsl]]--
    (-on)._extend
    {
      (-_)
        ._call
        {
          id = "on{tail}";

          from_init = true;

          "on{tail}:down";
          "on{tail}:up";

          value = "on";

          handler = function(self, t, tail)
            self:ensure_is("tail", tail, "table")

            if self:good() then
              self:ensure("tail must not be empty", #tail > 0)
              for i = 1, #tail do
                self:ensure(
                    "tail[" .. i .. "] should be string or function",
                    is_string(tail[i]) or is_function(tail[i]),
                    type(tail[i])
                  )
              end
            end

            if self:good() then
              self:store_finalized_data()

              local reverse_tail = tireverse(tail)

              t.down =
              {
                reverse_tail = reverse_tail;
                handler = nil;
              }

              t.up =
              {
                reverse_tail = reverse_tail;
                handler = nil;
              }

            end
          end;
        }
        ._method_call
        {
          id = "on{tail}:down";

          from = "on{tail}";

          "on{tail}:up";
          false;

          value = "down";

          handler = function(self, t, _, handler)
            self:ensure_is("handler", handler, "function")

            self:ensure(
                "at most one :down per dsl construct allowed",
                not t.down.handler
              )

            if self:good() then
              t.down.handler = handler
            end
          end;
        }
        ._method_call
        {
          id = "on{tail}:up";

          from = "on{tail}";

          "on{tail}:down";
          false;

          value = "up";

          handler = function(self, t, _, handler)
            self:ensure_is("handler", handler, "function")

            self:ensure(
                "at most one :up per dsl construct allowed",
                not t.up.handler
              )

            if self:good() then
              t.up.handler = handler
            end
          end;
        }
        ;
    }
  end

  local mt_index = function(t, k)
    -- NOTE: Optimizable. At least we could use prefix tree here.
    local handlers = getmetatable(t).handlers
    for i = 1, #handlers do
      local v = handlers[i](k)

      -- NOTE: We pick first matching rule now, whatever it is.
      --       "Most specialized rule wins" feature would be useful.
      if v ~= nil then
        return v -- Not memoizing
      end
    end

    return nil -- Not found
  end

  create_path_mt = function(path_mt_dsl_chunk)
    arguments(
        "function", path_mt_dsl_chunk
      )

    local rules = assert(
        do_in_common_dsl_environment(
            {
              dsl_fsm_bootstrap_chunk,
              path_mt_dsl,
              path_mt_dsl_chunk
            },
            { },
            create_dsl_env_mt(
                tset
                {
                  "_"; -- Needed for bootstrap
                  "on";
                }
              )
          )
      )

    local handlers = { down = { }, up = { } }
    for i = 1, #rules do
      for direction, rule in pairs(rules[i]) do
        local reverse_tail = rule.reverse_tail
        local handler = rule.handler
        handlers[direction][#handlers[direction] + 1] = function(path)
          return match_path(reverse_tail, path) and handler or nil
        end
      end
    end

    local down = setmetatable(
        { },
        {
          handlers = handlers.down;
          __index = mt_index;
        }
      )

    local up = setmetatable(
        { },
        {
          handlers = handlers.up;
          __index = mt_index;
        }
      )

    return down, up
  end
end

--------------------------------------------------------------------------------

return
{
  create_path_mt = create_path_mt;
}

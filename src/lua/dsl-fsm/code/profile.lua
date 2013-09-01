--------------------------------------------------------------------------------
-- pk-core.lua: dsl-fsm exports profile
-- This file is a part of le-dsl-fsm project
-- Copyright (c) LogicEditor <info@logiceditor.com>
-- Copyright (c) le-dsl-fsm authors
-- See file `COPYRIGHT` for the license.
--------------------------------------------------------------------------------

local tset = import 'lua-nucleo/table-utils.lua' { 'tset' }

--------------------------------------------------------------------------------

local PROFILE = { }

--------------------------------------------------------------------------------

PROFILE.skip = setmetatable(tset
{
}, {
  __index = function(t, k)
    -- Excluding files outside of pk-core/ and inside pk-core/code
    local v = (not k:match("^dsl%-fsm/"))
      or k:match("^dsl%-fsm/code/")
    t[k] = v
    return v
  end;
})

--------------------------------------------------------------------------------

return PROFILE

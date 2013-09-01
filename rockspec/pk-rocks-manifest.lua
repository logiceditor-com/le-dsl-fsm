--------------------------------------------------------------------------------
-- pk-rocks-manifest.lua: PK rocks manifest for le-dsl-fsm
-- This file is a part of le-dsl-fsm project
-- Copyright (c) LogicEditor <info@logiceditor.com>
-- Copyright (c) le-dsl-fsm authors
-- See file `COPYRIGHT` for the license.
--------------------------------------------------------------------------------

local ROCKS =
{
  {
    "rockspec/le-dsl-fsm-scm-1.rockspec";
    generator = { "rockspec/gen-rockspecs" };
  };
}

return
{
  ROCKS = ROCKS;
}

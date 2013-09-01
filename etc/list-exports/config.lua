--------------------------------------------------------------------------------
-- config.lua: list-exports configuration
-- This file is a part of le-dsl-fsm project
-- Copyright (c) LogicEditor <info@logiceditor.com>
-- Copyright (c) le-dsl-fsm authors
-- See file `COPYRIGHT` for the license.
--------------------------------------------------------------------------------
-- Note that PROJECT_PATH is defined in the environment
--------------------------------------------------------------------------------

common =
{
  PROJECT_PATH = PROJECT_PATH;

  exports =
  {
    exports_dir = PROJECT_PATH .. "/src/lua/dsl-fsm/code/";
    profiles_dir = PROJECT_PATH .. "/src/lua/dsl-fsm/code/";

    sources =
    {
      {
        sources_dir = PROJECT_PATH .. "/src/lua/";
        root_dir_only = "dsl-fsm";
        lib_name = "dsl-fsm";
        profile_filename = "profile.lua";
        out_filename = "exports.lua";
        file_header = [[
-- This file is a part of le-dsl-fsm project
-- Copyright (c) LogicEditor <info@logiceditor.com>
-- Copyright (c) le-dsl-fsm authors
-- See file `COPYRIGHT` for the license.
]]
      };
    };
  };
}

--------------------------------------------------------------------------------

list_exports =
{
  action =
  {
    name = "help";
    param =
    {
      -- No parameters
    };
  };
}

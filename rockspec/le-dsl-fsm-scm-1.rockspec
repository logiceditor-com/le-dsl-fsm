package = "le-dsl-fsm"
version = "scm-1"
source =
{
  url = "git://github.com/logiceditor-com/le-dsl-fsm.git";
  branch = "master";
}
description =
{
  summary = "The Lua DSL FSM library";
  homepage = "https://github.com/logiceditor-com/le-dsl-fsm";
  license = "MIT/X11";
  maintainer = "LogicEditor Team <team@logiceditor.com>";
}
dependencies =
{
  "lua == 5.1";
  "lua-nucleo";
  "lua-aplicado";
}
build =
{
  type = "builtin";
  modules =
  {
    ["dsl-fsm.bootstrap"] = "src/lua/dsl-fsm/bootstrap.lua";
    ["dsl-fsm.check"] = "src/lua/dsl-fsm/check.lua";
    ["dsl-fsm.code.exports"] = "src/lua/dsl-fsm/code/exports.lua";
    ["dsl-fsm.code.profile"] = "src/lua/dsl-fsm/code/profile.lua";
    ["dsl-fsm.common_env"] = "src/lua/dsl-fsm/common_env.lua";
    ["dsl-fsm.dsl_manager"] = "src/lua/dsl-fsm/dsl_manager.lua";
    ["dsl-fsm.util.path_mt"] = "src/lua/dsl-fsm/util/path_mt.lua";
  };
}

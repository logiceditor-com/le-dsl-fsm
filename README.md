le-dsl-fsm: The Lua DSL FSM library
===================================

Builiding internal Lua 5.1 Domain-Specific Languages as Finite State Machines.

<pre>
Copyright (c) 2013, LogicEditor <info@logiceditor.com>
Copyright (c) 2013, le-dsl-fsm authors (see `AUTHORS`)
</pre>

See file `COPYRIGHT` for the license.

## Project status

Current version v0.9.0 is a beta release.

The lua-dsl-fsm project is used in production, but is still under development.
Expect some changes in APIs and contracts.

Early adopters and pull-requests are very welcome.

## Overview

Lua, among its other virtues, is designed to be quite well suited to be used as
a data description language.

Ad-hoc internal (embedded) DSLs for data description can be built almost at
a whim.

This ease, as a project evolves and language grows, often results in a bunch
of hard to support spaghetti-like mess. Furthermore, while it is very easy
to build a small ad-hoc internal DSL in Lua, it is not so easy to implement
full-blown validation and comprehensible diagnostics for that DSL.

*Note on terminology: Internal or embedded DSLs are DSLs which [ab]use host
general-purpose language syntax to gave user a feeling that he is
writing in a different, domain-specific language. I.e. code in
internal Lua DSL is valid Lua code, that loadfile() would understand
without modifications.*

### Project goals

The Lua DSL FSM library aims to provide a standard and flexible way to create
internal domain-specific languages for Lua, and to help language authors
to ensure that their languages are maintainable and have proper validation
and diagnostics facilities.

*Note: user-friendliness of diagnostics is still far from perfect
in current version (v0.9.0), and is to be improved significantly
before the release. Please do report any flaws you find as bugs.
Pull requests are welcome as well. Validation support will also be improved.*

While the library focus is on declarative DSLs, it is generic enough
to allow other kinds of internal DSLs to be implemented.

### Basic internal Lua DSL constructs

```Lua
namespace:method "title"
{
  data = "here";
}
```

This is a construct that is commonly used as a basic building block of
internal declarative DSLs in Lua. Think about it as a configuration file format
section:

```
[branch "master"]
        remote = origin
        merge = refs/heads/master
```

In Lua:

```Lua
git:branch "master"
{
  remote = "origin";
  merge = "refs/heads/master";
}
```

Nesting is also commonly used, often in data format descriptions:

```Lua
cfg:namespace "git"
{
  cfg:node "branch"
  {
    cfg:string "remote";
    cfg:string "merge";
  };
}
```

There are several other DSL construct forms that are often found in the wild.
Note that `namespace` part is often dropped, especially in more primitive DSLs.

*Note: Some examples here are fictional. Pull-requests that help to improve
documentation by using real-life examples are very welcome.*

A handler function (from pk-test):

```Lua
test "expected-to-fail" (function()
  error("test failed as expected")
end)
```

Simple call chain (from Squish):

```Lua
Option "minify-level" "full"
```

Simple data table, order-dependent sections (from Premake):

```Lua
solution "MyApplication"
  configurations { "Debug", "Release" }

  project "MyApplication"
    kind "ConsoleApp"
    language "C++"
    files { "**.h", "**.cpp" }
```

Title and description (or, in this fictional example, a character and remark):

```Lua
play:remark [[Hamlet]]
[[
Alas, poor Yorick! I knew him, Horatio; a fellow of infinite jest, of most
excellent fancy; he hath borne me on his back a thousand times; and now,
how abhorred in my imagination it is!
]]
```

### Anatomy of an internal Lua DSL construct

All DSL constructs above are built upon a few basic tricks:

* Declarative call sugar: Lua allows parentheses to be dropped in
  a function call, if function is called with a single argument that is
  either a table literal or a string literal.

  Following calls are the same:

  ```Lua
  foo [[bar]]
  foo "bar"
  foo 'bar'
  ```

  ...and without sugar can be written as follows:

  ```Lua
  local tmp = _G["foo"]
  tmp("bar")
  ```

* Chained function calls: in Lua a function can return a function:

  ```Lua
  local function cat(str)
    io.stdout:write(tostring(str))
    return cat
  end

  cat "This" " is " "fun"
  ```

  Without sugar:

  ```Lua
  local tmp1 = cat("This")
  local tmp2 = tmp1(" is ")
  tmp2("fun")
  ```

Thus, our basic DSL building block:

```Lua
foo:bar "title"
{
  data = "here";
}
```

...without sugar will look as follows:

```Lua
_G["foo"]:bar(
    "title"
  )(
    {
      data = "here";
    }
  )
```

I.e. method `bar` of a global variable `foo`, is called with a single string
literal argument `"title"`. The method `bar` returns a function, which is
called in turn with a single table literal argument `{ data = "here"}`.

This micro-DSL can be naïvely implemented as follows:

```Lua
foo = -- A global variable.
{
  bar = function(name)
    return function(param)
      assert(name == "title")
      assert(type(param) == "table")
      assert(param.data == "here")
    end
  end;
}
```

Note that there is no protection from the common mistake that DSL users do --
it is too easy to omit a second call in the chain:

```Lua
foo:bar "where is the data?"
```

Alternatively, one might want to make second call optional as a feature:

```Lua
git:commit [[Short comment]]

git:commit [[Short comment]]
[[
Long description.
]]
```

There is no way to do that without seriously complicating the naïve approach.

Once DSL author begins to try to _evolve_ the naïve implementation so it would
handle such corner cases, the implementation quickly deteriorates into
a tangled mess of spaghetti code.

### On generic non-FSM approach to DSL implementation

There is a less naïve generic way of handling DSLs, described in
a Lua Workshop 2011 talk by one of `le-dsl-fsm` authors:
http://bit.ly/lua-dsl-talk.

Several basic ideas from that approach are used in this library, so a brief
outline is given here. Please refer to the talk slides for more details
(you can also find some more examples of complex DSL constructs there).

This older approach does work as follows:

1.  All DSL constructs are converted to plain Lua tables by the core DSL code,
    using a set of semi-hardcoded rules:

    In DSL:

    ```Lua
    foo:bar "title"
    {
      data = "here";
    }
    ```

    In memory (none non-hygienic `id` and `name` keys):

    ```Lua
    {
      id = "foo:bar";
      name = "title";
      data = "here";
    }
    ```

    All non-trivial validation and actual data processing is then done with
    these tables.

    Nested DSL constructs naturally result in nested tables:

    In DSL:

    ```Lua
    cfg:node "branch"
    {
      cfg:string "remote";
    }
    ```

    In memory:

    ```Lua
    {
      id = "cfg:node";
      name = "branch";
      {
        id = "cfg:string";
        name = "remote";
      };
    }
    ```

2.  The conversion rules support a limited set of DSL construct forms,
    each new form requires non-trivial core DSL library code modification.
    (See slides for a list of supported forms.)

3.  Debug information (file and line for the first call in chain for the
    DSL construct) is stored alongside with construct's data to allow
    for nice error messages when validation code detects an error.

3.  Actual conversion is done by a proxy object which collects the data.

    A simplified illustrative example of such proxy object:

    ```Lua
    local proxy = function(namespace)
      return setmetatable(
          { },
          {
            __index = function(t, tag)
              return function(data)
                data.id = namespace .. ":" .. tag
                return data
              end
            end;
          }
        )
    end

    foo = proxy("foo") -- A global variable
    ```

    Not shown in the example:
    * Source location capture in `__index`. Done via `debug.getinfo()`.
    * Support for multiple DSL construct forms.
    * Dangling (or optional) data call handling. All proxies are registered
     in a global manager object, and then cleaned up after DSL is loaded.

4.  DSL code is executed in a special global environment, with `__index`
    set to return a proxy object for each unknown global read.

    A simplified illustrative example:

    ```Lua
    local chunk = function() -- Usually returned by loadfile().
      foo:bar "title"
      {
        data = "here";
      }
    end

    local proxy_manager = ...

    local env = setmetatable(
        {
          print = print; -- For debugging
        },
        {
          __index = function(t, namespace)
            return proxy_manager:proxy(namespace)
          end;
        }
      )

    setfenv(chunk, env)
    chunk() -- Usually an xpcall() with advanced error handling.

    local dsl_objects = proxy_manager:result()
    ```

    Note that proxy objects are not cached -- each global lookup should
    result in a new proxy being created, so multiple `foo:bar` calls would
    create separate DSL table objects.

5.  Table hierarchies are then traversed depth-first, with user-supplied
    callbacks on downward and upward node traversal for each node `id`.

    A simplified illustrative example:

    ```Lua
    local walkers = { down = { }, up = { } }

    setmetatable(
        walkers.down,
        {
          __index = function(t, id)
            error("unknown DSL construct `" .. tosting(id) .. "'")
          end;
        }
      )

    walkers.down["foo:bar"] = function(self, node)
      io.stdout:write("<foo:bar name=", xml_escape(node.name), ">\n",)
    end

    walkers.down["foo:cdata"] = function(self, node)
      io.stdout:write("<![CDATA[", cdata_escape(node.text), "]]>\n")
    end

    walkers.up["foo:bar"] = function(self, node)
      io.stdout:write("</foo:bar>\n")
    end

    handle_dsl(function()
      foo:bar "baz"
      {
        foo:cdata [[quo]];
      }
    end)

    --> Should print:
    --> <foo:bar name="baz">
    -->   <![CDATA[quo]]>
    --> </foo:bar>
    ```

This approach to building DSLs works, but it lacks flexibility. Each new DSL
using it would be like all others. But, as we can see from examples, not
every DSL needs to use namespaces, some tend to use unlimited chain calls,
etc. etc. Hardcoded DSL forms are the main limitation.

Each new supported DSL form would bloat the code DSL handling code even more.
The implementation would become truly spaghetti-like to support something
like this DSL construct:

```Lua
play:scene [[SCENE II]]

.location [[Another room in the castle.]]

:enter "HAMLET"

:remark "HAMLET"
[[
Safely stowed.
]]

:remark { "ROSENCRANTZ", "GILDERSTERN" } .cue [[within]]
[[
Hamlet! Lord Hamlet!
]]

:remark "HAMLET"
[[
What noise? who calls on Hamlet?
O, here they come.
]]
```

## The Finite State Machine approach

**TODO: document!**

## Some additional remarks on the design

### On performance

While `le-dsl-fsm` is perfectly suited to work in run-time, it is currently
primarily used for off-line code generation, where speed is usually
not an issue.

The code should be fast enough to e.g. load a config file in run-time at
a start of a program, or, say, build a validator for HTTP GET request
parameters. But it is not intended to, say, load DSL code per each HTTP request.

That being said, any pull-requests that optimize and improve performance
of `le-dsl-fsm` would be very welcome.

No matter of how you'd like to use the library, if you ever find that
`le-dsl-fsm` is too slow for you, please do file a bug report,
detailing your use case.

### On Lua language version

The `le-dsl-fsm` library supports Lua 5.1 (and LuaJIT 2.0+).

Support for Lua 5.2+ is not planned, but can be added if someone will
provide a non-intrusive and easy to support pull-request or will sponsor
a port.

# Installation

**TODO: document!**

### On Lua-Núcleo dependency

**TODO: document: optional import, how to disable strict**

### On pk-test dependency

**TODO: document!**

# Reference

## DSL FSM format

**TODO: document!**

## DSL manager

**TODO: document!**

## Common DSL environment

**TODO: document!**

## Bootstrap meta-DSL

**TODO: document!**

# Examples

See tests.

**TODO: Provide proper examples that are easier to read than tests.**

# Bug reports and support

For bug reports and feature requests, please use GitHub issue system:

https://github.com/logiceditor-com/le-dsl-fsm/issues

For public support, please ask a question at http://stackoverflow.com,
and send a link to it to a project maintainer,
Alexander Gladysh at ag@logiceditor.com. You can also use Lua mailing list,
but please CC the maintainer and write `lua-dsl-fsm` somewhere in the subject.

Private consulting is available on commercial basis. Should you need it,
please contact LogicEditor at consulting@logiceditor.com.

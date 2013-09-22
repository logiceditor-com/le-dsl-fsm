le-dsl-fsm: The Lua DSL FSM library
===================================

Building internal Lua 5.1 Domain-Specific Languages as Finite-State Machines.

<pre>
Copyright (c) 2013, LogicEditor <info@logiceditor.com>
Copyright (c) 2013, le-dsl-fsm authors (see `AUTHORS`)
</pre>

See file `COPYRIGHT` for the license.

**TODO: We need a TOC, generate one**
**TODO: We also need a short tl;dr description before that wall of text.**

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
internal Lua DSL is valid Lua code, that `loadfile()` would understand
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

    In memory (note non-hygienic `id` and `name` keys):

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

## The Finite-State Machine approach

### A generic DSL proxy object

Lets review our DSL construct:

```Lua
foo:bar "title"
{
  data = "here";
}
```

It is a series of index and call operations:

```Lua
local foo = _G["foo"]
local bar = foo["bar"]
local tmp = bar(foo, "title")
tmp({ data = "here"})
```

It is possible to build a proxy object that returns itself from `__index`
and `__call` metamethods:

```Lua
require 'lua-nucleo.import'
local tstr = import 'lua-nucleo/tstr.lua' { 'tstr' } -- Table serialization
local proxy = function(namespace)
  local self = { }
  local method_name = nil

  io.write(namespace)

  return setmetatable(
      self,
      {
        __index = function(t, k)
          io.write(("[%q]"):format(tostring(k)))
          return self
        end;

        __call = function(t, ...)
          method_call = (select(1, ...) == self)
          need_comma = false

          io.write("(")
          for i = 1, select("#", ...) do
            if i == 1 and method_call then
              io.write(namespace)
            else
              io.write(
                  need_comma and ", " or "",
                  tstr( (select(i, ...)) )
                )
            end
            need_comma = true
          end
          io.write(")")
          return self
        end;
      }
    )
end

setmetatable(_G, { __index = function(t, k) return proxy(k) end })
```

This would allow us to load any sane DSL construct:

```Lua
foo:bar "title"
  .alpha
  .beta "gamma"
{
  data = "here";
}
--> Should print:
--> foo["bar"](foo, "title")["alpha"]["beta"]("gamma")({data="here"})
```

Note that, obviously, for every single given DSL construct the operation
(index or call) chain would always be linear. Call goes after index after call,
and so on, one after another.

### The DSL FSM

While our generic DSL proxy approach allows us to load _any_ DSL construct,
we (usually) do not want to.

If we have to be able to load any possible DSL construct, we'd have to store
loaded data in a generic form that can represent _any_ possible construct.
And the validation would have to be done later anyway, so we would not actually
win anything, just complicate things.

Much better to fail early on invalid constructs, and get rid of intermediate
data representation altogether. DSL library user does not want to deal with
DSL data tree, he needs to work with his problem-specific data.

To achieve early validation we can describe our proxy behavior as a
finite-state machine where each operation (index or call) would be a state
transition.

For example, for our `foo:bar` example with `foo:cdata`:

```Lua
foo:bar "baz"
{
  foo:cdata [[quo]];
}
```

...FSM can be described as follows (in pseudocode):

*TODO: Try to find a commonly understood _text-based_ format
for FSM descriptions, do not invent yet another one.*

```
INIT | index "bar" -> foo.bar
       foo.bar | call -> foo.bar.name
  foo.bar.name | call -> foo.bar.name.param
FINAL <- foo.bar.name.param

INIT | index "cdata" -> foo.cdata
  foo.cdata | call -> foo.cdata.text
FINAL <- foo.cdata.text
```

Several things to note here:

* On this level of abstraction method calls (`foo:bar()`) can not be
  distinguished from field calls (`foo.bar()`) or even from plain calls
  (`foo()`). Such distinction is to be done somewhere on higher level
  (we'll get to that later).

* There can be several different index operation transitions defined
  for each state (including initial but excluding terminal ones).

  However there can be at most one call operation transition for a given state
  (because it is not possible to separate one call from another without
  looking at arguments, and we choose not to do so at this low level).

  A state may have both index (zero to many) and call (at most one)
  transitions.

* Terminal (`FINAL`) state is described explicitly, separately from actual
  terminal states (`foo.bar""{}` and `foo.cdata[[]]`). It is easier
  to manage when one has many routes to the terminal state and one has
  to provide a handler to do something when the final state is reached.
  More on that later.

  A state may have at most one terminal transition.

* Each state in the FSM must be reachable from the `INIT` state. The `FINAL`
  state must be reachable from every other state in the FSM.

### State transition handlers

*NOTE: At this point, we let user provide not state transition handlers,
but less generic and less flexible state entrance handlers.
TODO: Probably a redesign is in order.*

Now we can describe our DSL as a set of FSM states with state transition
handlers, and teach our generic DSL proxy object to adhere to transition
rules and call the appropriate handlers when needed.

Here is a simplified illustrative example of the XML output example seen above:

*Note: See below for full DSL FSM data format documentation.*

```Lua
local fsm =
{
  id = "foo";

  init =
  {
    "foo.bar";
    "foo.cdata";
  };

  states =
  {
    [false] = true; -- Use default terminal state handler

    ["foo.bar"] =
    {
      type = "index", id = "foo.bar";

      "foo.bar.name";

      value = "bar";
    };

    ["foo.bar.name"] =
    {
      type = "call", id = "foo.bar.name";

      "foo.bar.name.param";

      handler = function(self, t, _, name)
        -- `_' is `self' of method call, we ignore it
        t.name = name -- Validation not shown for readability
      end;
    };

    ["foo.bar.name.param"] =
    {
      type = "call", id = "foo.bar.name.param";

      false; -- Terminal state

      handler = function(self, t, param)
        io.write("<foo name=", xml_escape(t.name), ">\n")
        for i = 1, #param do
          if type(param[i]) == "table" then
            io.write(assert(param[i].xml))
          else
            io.write(tostring(param[i]))
          end
        end
        io.write("</foo>\n")
      end;
    };

    ["foo.cdata"] =
    {
      type = "index", id = "foo.cdata";

      "foo.cdata.text";

      value = "cdata";
    };

    ["foo.cdata.text"] =
    {
      type = "call", id = "foo.bar.text";

      handler = function(self, t, _, text)
        t.xml = "<![CDATA[" .. cdata_escape(text) .. "]]>\n"
      end;
    };
  };
}
```

Here we did render XML code directly. It is useful for simpler cases,
but for more complex DSLs, a problem-specific intermediate data format
of some kind is still likely to be needed. So, if we'd wanted to,
we could instead produce a table hierarchy, compatible with up/down walker
code shown above:

```Lua
local fsm =
{
  id = "foo";

  init =
  {
    "foo.bar";
    "foo.cdata";
  };

  states =
  {
    [false] = true; -- Use default terminal state handler

    ["foo.bar"] =
    {
      type = "index", id = "foo.bar";

      "foo.bar.name";

      value = "bar";
    };

    ["foo.bar.name"] =
    {
      type = "call", id = "foo.bar.name";

      "foo.bar.name.param";

      handler = function(self, t, _, name)
        t.name = name
      end;
    };

    ["foo.bar.name.param"] =
    {
      type = "call", id = "foo.bar.name.param";

      false; -- Terminal state

      handler = function(self, t, param)
        param.id = "foo:bar"
        param.name = t.name
        -- Tell the framework that we'd like to replace `t' with `param'
        return param
      end;
    };

    ["foo.cdata"] =
    {
      type = "index", id = "foo.cdata";

      "foo.cdata.text";

      value = "cdata";
    };

    ["foo.cdata.text"] =
    {
      type = "call", id = "foo.bar.text";

      handler = function(self, t, _, text)
        t.id = "foo:cdata"
        t.text = text
      end;
    };
  };
}
```

Suddenly, even the most Byzantine DSL constructs start to look easier
to implement. That being said, this is a very low level format of
DSL description, and a lot of boilerplate code is to be expected.
We'll tackle that later.

### On DSL proxy finalization

Our new FSM-based approach to DSL implementation has an interesting side-effect:
now we can know when we can finalize our proxy object and replace it with actual
data.

For the FSM from the last example, whenever proxy object reaches a terminal
state, it can be automatically finalized and replaced with its data (`t`
argument in handlers).

A DSL FSM proxy object is always an empty table with a fancy metatable set
to it. All proxy object data is stored in that metatable, not in the table. This
way, if we remove the metatable and copy all `t` keys and values to that table,
we'll effectively get the finalized data object right in the same place where
proxy object was. (Of course, all references to `t` would no longer be valid,
but it is a small price to pay.)

For the last `foo:cdata` example above:

```Lua
foo:bar "baz"
{
  foo:cdata [[quo]];
}
```

...Before finalization, in pseudocode:

```Lua
PROXY "bar"
{
  t =
  {
    id = "foo:bar";
    name = "baz";

    PROXY "cdata"
    {
      t =
      {
        id = "foo:cdata";
        text = "quo";
      };
    };
  };
}
```

...After finalization:

```Lua
{
  id = "foo:bar";
  name = "baz";

  {
    id = "foo:cdata";
    text = "quo";
  };
}
```

To simplify handler code, current implementation automatically finalizes
all proxies that are passed as arguments to the handler (including
table keys and values). That is why in a previous FSM example we could
access `param[i].xml` from `foo:cdata` directly in the `foo:bar` handler:

```Lua
handler = function(self, t, param)
  io.write("<foo name=", xml_escape(t.name), ">\n")
  for i = 1, #param do
    if type(param[i]) == "table" then
      io.write(assert(param[i].xml)) -- param[i] is a finalized proxy
    else
      io.write(tostring(param[i]))
    end
  end
  io.write("</foo>\n")
end;
```

Things become a little more complicated when the terminal state is not the
only one possible transition from a given state.

A synthetic micro-example:

```Lua
cat "this" " is " "fun"
```

This micro-DSL can be described as follows:

```Lua
local fsm =
{
  id = "cat";

  init =
  {
    "call";
  };

  states =
  {
    [false] = true; -- Use default terminal state handler

    ["call"] =
    {
      type = "call", id = "call";

      "call"; -- A self-reference
      false; -- Terminal state

      handler = function(self, t, text)
        io.stdout:write(text)
      end;
    };
  };
}
```

Here we can't immediately know if the proxy reached its final state,
or if a next `"call"` state would follow.

This is why we still have to keep a DSL [proxy] manager object, which
tracks all proxies, and is responsible for their late finalization.

Luckily, since all proxies are tables, late finalization does not prevent them
from being finalized in-place, the same as with auto-finalization, described
above.

**TODO: Describe why one would want to use `self:store_finalized_data()`**

### Meta: on-the-fly FSM modifications

**TODO: document!**

#### Meta-handlers

### Common DSL environment

**TODO: document!**

### Low-level bootstrap

**TODO: document!**

### Higher-level bootstraps

**TODO: document!**

## Some additional remarks on the implementation

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

## Helper object API

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

# TODO

* Create GH issues for all TODO items in text and code.
* Test that all code examples in this document actually work.

# SPDX-FileCopyrightText: © 2025 TEC <contact@tecosaur.net>
# SPDX-License-Identifier: MPL-2.0

module Trash

using Dates

export trash, untrash, TrashFile

@static if VERSION >= v"1.11"
    eval(Expr(:public, :trashdir, :trashes, :list, :search, :empty))
end

include("generic.jl")

const PLATFORM = @static if Sys.isapple()
    include("darwin.jl")
    :darwin
elseif Sys.isunix()
    include("freedesktop.jl")
    :freedesktop
elseif Sys.iswindows()
    include("windows.jl")
    :nt
end

precompile(trash, (String,))
precompile(untrash, (TrashFile,))
precompile(untrash, (String,))
precompile(list, ())
precompile(list, (String,))
precompile(search, (String,))
precompile(trashdir, ())
precompile(trashdir, (String,))
precompile(trashes, ())
precompile(empty, ())
precompile(empty, (String,))

@doc """
    Trash

Cross-platform file trashing library.

Move files and directories to your system's trash rather than deleting
them outright, and manage trashed items programmatically:

- `trash(path)`: send a file or folder to Trash.
- `trashdir(path)`: find the directory of the trash that would be used for a certain path.
- `list([trashdir])`: list all trashed items as a `Vector{TrashFile}` (with original paths and deletion timestamps).
- `untrash(entry; pick=:only, force=false, rm=false)`: restore one trashed item
  (choose oldest/newest on duplicates; handle conflicts). This operates on both `TrashFile` entries, and
  the original path to a file or folder that has been deleted.
- `empty([trashdir])`: empty the trash directory (permanently delete all items in it).

# Examples

```julia-repl
julia> using Trash

julia> write("demofile", "some content")
12

julia> trash("demofile")
TrashFile("/tmp/demofile" @ $(Date(now())))

julia> write("demofile", "newer, better(?) content")
12

julia> trash("demofile")
TrashFile("/tmp/demofile" @ $(Date(now())))

julia> Trash.search("demofile")
2-element Vector{TrashFile}:
 TrashFile("/tmp/demofile" @ $(Date(now())))
 TrashFile("/tmp/demofile" @ $(Date(now())))

julia> untrash("demofile", pick = :oldest)
"demofile"

julia> read("demofile", String)
"some content"

julia> untrash("demofile", force = true)
"demofile"

julia> read("demofile", String)
"newer, better(?) content"
```
""" Trash

end

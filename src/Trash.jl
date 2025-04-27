module Trash

using Dates

export trash, untrash, TrashFile

@static if VERSION >= v"1.11"
    eval(Expr(:public, :list, :empty))
end

"""
    TrashFile

A representation of a file that has been trashed.

This file contains the path to the original file, the time it was trashed, and
where it has been moved to in the trash.
"""
struct TrashFile
    trashfile::String
    path::String
    dtime::DateTime
end

function Base.show(io::IO, tf::TrashFile)
    if get(io, :limit, false) === true
        show(io, TrashFile)
        print(io, '(')
        show(io, tf.path)
        printstyled(io, " @ ", Date(tf.dtime), color=:light_black)
        print(io, ')')
    else
        Base.show_default(io, tf)
    end
end

"""
    trash(path::String; force::Bool=false)

Put the file, link, or empty directory in the system trash. If `force=true` is
passed, a non-existing path is not treated as an error.

See also: [`Trash.list`](@ref), [`untrash`](@ref).
"""
function trash end

# TODO see if `trashdir` is cross-platform enough

"""
    list() -> Vector{TrashFile}

List all entries currently in the user's trash.

See also: [`trash`](@ref), [`untrash`](@ref).
"""
function list end

@doc """
    list(trashdir::String) -> Vector{TrashFile}

List all entries currently in the trash directory `trashdir`.
""" list(::String)

"""
    untrash(entry::TrashFile, dest::String = original path;
            force::Bool = false, rm::Bool = false)

Restore a file, link, or directory represented by `entry` from the system trash.

The entry will be restored to the path `dest`, which defaults to the original
location of the `entry`.

If `force` is `true`, any existing file at the destination will be trashed,
and if `rm` is `true`, the file will be removed with `Base.rm`.

See also: [`trash`](@ref), [`Trash.list`](@ref).
"""
function untrash end

"""
    untrash(path::String, dest::String = path; pick::Symbol = :only,
            force::Bool = false, rm::Bool = false)

Restore the original contents of `path`, optionally specifying a different `dest`ination.

Should multiple entries of `path` exist in the trash, an entry will be
chosen based on the `pick` option. The default is `:only`, which will throw an
`ArgumentError` if multiple entries are found. The other options are `:newest` and
`:oldest`, which will select the most recent or oldest entry, respectively.

The `force` and `rm` options are passed through to the `untrash(::TrashFile)` function.
"""
function untrash(path::String, dest::String=path;
                 force::Bool=false, rm::Bool=false, pick::Symbol = :only)
    candidates = search(path)
    entry = if isempty(candidates)
        throw(ArgumentError("$(sprint(show, path)) is not present in the trash."))
    elseif length(candidates) == 1
        first(candidates)
    elseif pick === :newest
        first(findmax(e -> e.dtime, candidates))
    elseif pick === :oldest
        first(findmin(e -> e.dtime, candidates))
    elseif pick === :only
        throw(ArgumentError("Multiple $(length(candidates)) trash candidates for $(sprint(show, path)), please use `pick=:newest` or `pick=:oldest` to select one."))
    else
        throw(ArgumentError("Invalid `pick` option: $(sprint(show, pick)). Use `:newest`, `:oldest` or `:only`."))
    end
    # Restore the file
    untrash(first(candidates), dest; force, rm)
end

"""
    search(path::String) -> Vector{TrashFile}

Search for `path` entries in the trash.
"""
function search(path::String)
    entries = TrashFile[]
    if endswith(path, '/')
        path = path[1:prevind(path, end)]
    end
    path = abspath(path)
    for entry in list(trashdir(path))
        entry.path == path && push!(entries, entry)
    end
    entries
end

"""
    empty()

Empty the user trash.

See also: [`trash`](@ref), [`Trash.list`](@ref).
"""
function empty end

@doc """
    empty(trashdir::String)

Empty the trash directory `trashdir`.
""" empty(::String)

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

end

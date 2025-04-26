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
    untrash(entry::TrashFile; force::Bool=false, rm::Bool=false)

Restore a file, link, or directory represented by `entry` from the system trash.

If `force` is `true`, any existing file at the destination will be trashed,
and if `rm` is `true`, the file will be removed with `Base.rm`.

See also: [`trash`](@ref), [`Trash.list`](@ref).
"""
function untrash end

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

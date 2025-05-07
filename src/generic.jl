# SPDX-FileCopyrightText: © 2025 TEC <contact@tecosaur.net>
# SPDX-License-Identifier: MPL-2.0

# Generic code that is not specific to any backend,
# as well as the API that is implemented by specific backends.


# Types

"""
    TrashFile

A representation of a file that has been trashed.

This representation contains:
- the path to the trash file,
- the path to the original file, and
- the time it was trashed
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

struct TrashFileMissing <: Exception
    path::String
    seen::Bool
end

TrashFileMissing(tf::TrashFile) =
    TrashFileMissing(tf.path, true)

function Base.showerror(io::IO, ex::TrashFileMissing)
    print(io, "TrashFileMissing: ", ex.path, if ex.seen
              "\n  This is likely because the trash has been emptied or this file restored from the trash."
          else
              "\n  Perhaps it never was, are you sure you passed the right path?\
              \n  Otherwise it's likely because the trash has been emptied or the path already restored."
          end)
end

struct TrashSystemError <: Exception
    callname::String
    msg::Union{String, Nothing}
    code::Union{Int, Nothing}
end

@static if Sys.iswindows()
    TrashSystemError(callname::String) =
        TrashSystemError(callname, nothing, Base.Libc.GetLastError())
else
    TrashSystemError(callname::String) =
        TrashSystemError(callname, nothing, Base.Libc.errno())
end

TrashSystemError(callname::String, msg::String) =
    TrashSystemError(callname, msg, nothing)

function Base.showerror(io::IO, ex::TrashSystemError)
    msg = ex.msg
    if isnothing(msg) && !isnothing(ex.code)
        msg = @static if Sys.iswindows()
            Base.Libc.FormatMessage(ex.code % UInt32)
        else
            Base.Libc.strerror(ex.code)
        end
    end
    print(io, "TrashSystemError")
    isempty(ex.callname) || print(io, ": ", ex.callname)
    isnothing(msg) || print(io, ": ", msg)
    isnothing(ex.code) || print(io, " (code: ", ex.code, ")")
    nothing
end


# Trash backend API

"""
    trash(path::String; force::Bool=false)

Put the file, link, or empty directory in the system trash. If `force=true` is
passed, a non-existing path is not treated as an error.

See also: [`Trash.list`](@ref), [`untrash`](@ref).
"""
function trash end

"""
    trashdir() -> String

Return the general trash directory for the current user.
"""
function trashdir end

@doc """
    trashdir(path::String) -> String

Return the trash directory used for `path`.
""" trashdir(::String)

"""
    list() -> Vector{TrashFile}

List all entries current in an accessible trash directory.

This searches the system for trash directories on local, mounted, writable
filesystems (including removable drives) and combines results into a single
list.

Filesystems that are network-based (e.g. NFS, SMB, or SSHFS) are skipped.

See also: [`trash`](@ref), [`untrash`](@ref).
"""
function list end

@doc """
    list(trashdir::String) -> Vector{TrashFile}

List all entries currently in the trash directory `trashdir`.

See also: [`trashdir`](@ref), [`search`](@ref).
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
    empty()

Empty the user trash.

See also: [`trash`](@ref), [`Trash.list`](@ref).
"""
function empty end

@doc """
    empty(trashdir::String)

Empty the trash directory `trashdir`.
""" empty(::String)


# Generic implementations

"""
    untrash(path::String, dest::String = path; pick::Symbol = :only,
            force::Bool = false, rm::Bool = false)

Restore the original contents of `path`, optionally specifying a different `dest`ination.

The `path` is the original path of the file or directory to be restored, and has
no connection to how the resource is stored in the trash.

Should multiple entries of `path` exist in the trash, an entry will be
chosen based on the `pick` option. The default is `:only`, which will throw an
`ArgumentError` if multiple entries are found. The other options are `:newest` and
`:oldest`, which will select the most recent or oldest entry, respectively.

The `force` and `rm` options are passed through to the `untrash(::TrashFile)` function.
"""
function untrash(path::String, dest::String=path;
                 force::Bool=false, rm::Bool=false, pick::Symbol = :only)
    path = abspath(path)
    candidates = search(path)
    entry = if isempty(candidates)
        throw(TrashFileMissing(path, false))
    elseif length(candidates) == 1
        first(candidates)
    elseif pick === :newest
        argmax(e -> e.dtime, candidates)
    elseif pick === :oldest
        argmin(e -> e.dtime, candidates)
    elseif pick === :only
        throw(ArgumentError("Multiple $(length(candidates)) trash candidates for $(sprint(show, path)), please use `pick=:newest` or `pick=:oldest` to select one."))
    else
        throw(ArgumentError("Invalid `pick` option: $(sprint(show, pick)). Use `:newest`, `:oldest` or `:only`."))
    end
    untrash(entry, dest; force, rm)
end

"""
    search(path::String) -> Vector{TrashFile}

Search for `path` entries in the trash.

This is a minor convenience function on top of [`list`](@ref), which see.
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

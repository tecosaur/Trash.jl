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

struct TrashAmbiguity <: Exception
    candidates::Vector{TrashFile}
end

function Base.showerror(io::IO, ex::TrashAmbiguity)
    println(io, "TrashAmbiguity: ", length(ex.candidates), " candidates found")
    for cand in sort(ex.candidates, by = x -> x.dtime)
        print(io, "  • ", basename(cand.path))
        if isdir(cand.trashfile)
            print(io, Base.Filesystem.path_separator)
        end
        if isdir(cand.trashfile)
            printstyled(io, " (", length(readdir(cand.trashfile)), " items)", color=:light_cyan)
        else
            printstyled(io, " (", Base.format_bytes(filesize(cand.trashfile)), ")", color=:light_cyan)
        end
        printstyled(io, " @ ", cand.dtime, color=:light_black)
        println(io)
    end
    print(io, "\n Use ")
    printstyled(io, "untrash", color=:blue)
    print(io, '(')
    printstyled(io, "...", color=:light_black)
    print(io, "; ")
    printstyled(io, "pick", color=:yellow)
    printstyled(io, " = ", color=:light_red)
    printstyled(io, ":newest", color=:magenta)
    printstyled(io, " or ", color=:light_black)
    printstyled(io, ":oldest", color=:magenta)
    print(io, ") to select one of the candidates,")
    print(io, "\n or manually filter the list of candidates from ")
    printstyled(io, "Trash.list", color=:blue)
    print(io, " or ")
    printstyled(io, "Trash.search", color=:blue)
    println(io, " yourself.")
end


# Trash backend API

function trash end

@doc """
    trash(path::String; force::Bool=false)

Put the file, link, or empty directory in the system trash. If `force=true` is
passed, a non-existing path is not treated as an error.

See also: [`Trash.list`](@ref), [`untrash`](@ref).
""" trash(::String; force::Bool=false)

function trashdir end

@doc """
    trashdir() -> String

Return the general trash directory for the current user.
""" trashdir()

@doc """
    trashdir(path::String) -> String

Return the trash directory used for `path`.
""" trashdir(::String)

function trashes end

@doc """
    trashes() -> Vector{String}

Return a list of all trash directories on the system.
""" trashes()

function list end

@doc """
    list() -> Vector{TrashFile}

List all entries current in an accessible trash directory.

This searches the system for trash directories on local, mounted, writable
filesystems (including removable drives) and combines results into a single
list.

Filesystems that are network-based (e.g. NFS, SMB, or SSHFS) are skipped.

See also: [`trash`](@ref), [`untrash`](@ref), [`orphans`](@ref).
""" list()

@doc """
    list(trashdir::String) -> Vector{TrashFile}

List all entries currently in the trash directory `trashdir`.

See also: [`trashdir`](@ref), [`search`](@ref).
""" list(::String)

function untrash end

@doc """
    untrash(entry::TrashFile, dest::String = original path;
            force::Bool = false, rm::Bool = false)

Restore a file, link, or directory represented by `entry` from the system trash.

The entry will be restored to the path `dest`, which defaults to the original
location of the `entry`.

If `force` is `true`, any existing file at the destination will be trashed,
and if `rm` is `true`, the file will be removed with `Base.rm`.

See also: [`trash`](@ref), [`Trash.list`](@ref).
""" untrash(::TrashFile, ::String; force::Bool, rm::Bool)

@doc """
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
""" untrash(::String, ::String; pick::Symbol, force::Bool, rm::Bool)

function search end

@doc """
    search(path::String) -> Vector{TrashFile}

Search for `path` entries in the trash.

This is a minor convenience function on top of [`Trash.list`](@ref), which see.
""" search(::String)

function orphans end

@doc """
    orphans() -> Vector{TrashFile}

List all entries in the trash that are missing data or metadata.

Orphaned entries can occur when an operation has been interrupted, encountered
an unexpected state and failed halfway, or when either a non-compliant tool
or user has been fiddling with the trash directory.

Dangling data produces `TrashFile` entries with an empty path, while dangling
metadata produces full `TrashFile` entries that cannot be restored.

This searches the system for trash directories on local, mounted, writable
filesystems (including removable drives) and combines results into a single
list.

Filesystems that are network-based (e.g. NFS, SMB, or SSHFS) are skipped.

See also: [`Trash.list`](@ref), [`Trash.purge`](@ref).
""" orphans()

@doc """
    orphans(trashdir::String) -> Vector{TrashFile}

List all entries in the trash directory `trashdir` that are missing data or metadata.
""" orphans(::String)

function purge end

@doc """
    purge(entry::TrashFile)

Permanently delete the entry `entry` from the trash.

To the extent possible, this will remove the data and metadata associated with
the entry, and will not be recoverable.

See also: [`Trash.list`](@ref), [`Trash.orphans`](@ref), [`Trash.empty`](@ref).
""" purge(::TrashFile)

function empty end

@doc """
    empty()

Empty the user trash.

See also: [`trash`](@ref), [`Trash.list`](@ref).
""" empty()

@doc """
    empty(trashdir::String)

Empty the trash directory `trashdir`.
""" empty(::String)

function localvolumes end

@doc """
    localvolumes() -> Vector{String}

List all accessible local (physical) volumes on the system.
""" localvolumes()


# Generic implementations

trashes() = filter(isdir, unique!(map(trashdir, localvolumes())))

list() = mapreduce(list, append!, trashes(), init=TrashFile[])

orphans() = mapreduce(orphans, append!, trashes(), init=TrashFile[])

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
        throw(TrashAmbiguity(candidates))
    else
        throw(ArgumentError("Invalid `pick` option: $(sprint(show, pick)). Use `:newest`, `:oldest` or `:only`."))
    end
    untrash(entry, dest; force, rm)
end

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

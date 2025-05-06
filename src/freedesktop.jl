# SPDX-FileCopyrightText: © 2025 TEC <contact@tecosaur.net>
# SPDX-License-Identifier: MPL-2.0

# See <https://specifications.freedesktop.org/trash-spec/trashspec-1.0.html>

const RFC3339 = dateformat"yyyy-mm-dd\THH:MM:SS"

function trash(path::String; force::Bool=false)
    path = abspath(path)
    ispath(path) || (force && return) ||
        throw(Base.IOError("trash($(sprint(show, path))) no such file or directory (ENOENT)", -Base.Libc.ENOENT))
    # Strip the trailing `/` from directories if needed
    if endswith(path, '/')
        path = path[1:prevind(path, end)]
    end
    # Determine the relevant paths
    tdir = trashdir(path)
    filesdir, infodir = joinpath(tdir, "files"), joinpath(tdir, "info")
    isdir(filesdir) || mkdir(filesdir)
    isdir(infodir) || mkdir(infodir)
    tname = trashname(path, tdir)
    trashpath = joinpath(filesdir, tname)
    # Write the `.trashinfo` file
    dtime = now()
    infofile = joinpath(infodir, tname * ".trashinfo")
    write(infofile,
          """
          [Trash Info]
          Path=$(rfc2396_escape(path))
          DeletionDate=$(Dates.format(dtime, RFC3339))
          """)
    # Move the file
    mv(path, trashpath)
    # Update directorysizes if needed
    if isdir(trashpath)
        dirsizes = open(joinpath(tdir, "directorysizes"), append = true)
        println(dirsizes, diskusage(trashpath), ' ',
                ceil(Int, mtime(infofile)), ' ',
                rfc2396_escape(tname))
        close(dirsizes)
    end
    TrashFile(trashpath, path, dtime)
end

function list(trashdir::String)
    entries = TrashFile[]
    isdir(joinpath(trashdir, "info")) || return entries
    for infofile in readdir(joinpath(trashdir, "info"), join=true)
        entry = trashinfo(infofile)
        !isnothing(entry) && push!(entries, entry)
    end
    entries
end

function list()
    trashes = unique!(map(trashdir, physicalvolumes()))
    mapreduce(list, append!, trashes, init=TrashFile[])
end

function empty(trashdir::String)
    infodir, filesdir = joinpath(trashdir, "info"), joinpath(trashdir, "files")
    isdir(infodir) && rm(infodir, force=true, recursive=true)
    isdir(filesdir) && rm(filesdir, force=true, recursive=true)
    mkdir(infodir)
    mkdir(filesdir)
    write(joinpath(trashdir, "directorysizes"), "")
    nothing
end

empty() = empty(trashdir())

function untrash(entry::TrashFile, dest::String = entry.path; force::Bool=false, rm::Bool=false)
    isfile(entry.trashfile) || throw(TrashFileMissing(entry))
    if ispath(dest)
        if rm
            Base.rm(dest, force=true, recursive=true)
        elseif force
            trash(dest)
        else
            throw(ArgumentError("$(sprint(show, dest)) already exists. `force=true` is required to remove it before restoring the trash entry."))
        end
    end
    # Restore file
    mv(entry.trashfile, dest)
    # Remove .trashinfo
    trashdir = dirname(dirname(entry.trashfile))
    infofile = joinpath(trashdir, "info", basename(entry.trashfile) * ".trashinfo")
    isfile(infofile) && Base.rm(infofile)
    # Update dirsizes if needed
    if isdir(dest) && isfile((dirsizesfile = joinpath(trashdir, "directorysizes");))
        dirsizes = IOBuffer(read(dirsizesfile))
        io = open(dirsizesfile, "w")
        for line in eachline(dirsizes)
            if sum(==(' '), line) >= 3
                size, mtime, path_esc = split(line, ' ', limit=3)
                path = rfc2396_unescape(path_esc)
                path != dest && println(io, line)
            end
        end
        close(io)
    end
    dest
end

function trashdir(path::String)
    mountroot = mountof(abspath(path))
    # Quick check if the user trash directory is best
    startswith(homedir(), mountroot) && return trashdir()
    # See if the devise has a `.Trash/`
    mounttrash = joinpath(mountroot, ".Trash")
    if isdir(mounttrash) && issticky(mounttrash) && !islink(mounttrash)
        # Since it exists and is valid, try the user-specific subdirectory
        mounttrash = joinpath(mounttrash, string(Base.Libc.getuid()))
        (isdir(mounttrash) || try mkdir(mounttrash); true catch _ false end) &&
            return mounttrash
    end
    # Fall back to `.Trash-$UID/`
    mounttrash = joinpath(mountroot, ".Trash-" * string(Base.Libc.getuid()))
    (isdir(mounttrash) || try mkdir(mounttrash); true catch _ false end) &&
        return mounttrash
    # Worst case, use the home trash anyway
    trashdir()
end

trashdir() = joinpath(get(ENV, "XDG_DATA_HOME", joinpath(homedir(), "~/.local/share")), "Trash")


# Helper functions

"""
    trashname(path::String, trashdir::String)

Obtain a unique trash file name for `path`.
"""
function trashname(path::String, trashdir::String)
    name = basename(path)
    !ispath(joinpath(trashdir, "info", name * ".trashinfo")) && return name
    suffixed, suffix = name, 0
    while ispath(joinpath(trashdir, "info", suffixed * ".trashinfo"))
        suffix += 1
        suffixed = string(name, " (", suffix, ')')
    end
    suffixed
end

"""
    mountof(path::String)

Find the parent mountpoint of `path`.
"""
function mountof(path::String)
    while !ismount(path)
        path = dirname(path)
    end
    path
end

"""
    trashinfo(infofile::String)

Try to parse the file `infofile` as a `TrashFile`, returning `nothing` if this
is not possible or valid for any reason.
"""
function trashinfo(infofile::String)
    # Check basics
    endswith(infofile, ".trashinfo") || return
    io = open(infofile, "r")
    readline(io) == "[Trash Info]" || return
    # Path
    pathline = readline(io)
    startswith(pathline, "Path=") || return
    path = rfc2396_unescape(pathline[length("Path=#"):end])
    isempty(path) && return
    # Date
    dateline = readline(io)
    startswith(dateline, "DeletionDate=") || return
    date = tryparse(DateTime, dateline[length("DeletionDate=#"):end], ISODateTimeFormat)
    isnothing(date) && return
    trashfile = joinpath(infofile |> dirname |> dirname, "files",
                         chopsuffix(basename(infofile), ".trashinfo"))
    TrashFile(trashfile, path, date)
end

"""
    diskusage(path::String)

Find the disk usage of `path`, in bytes (as `du -B1` does). This is almost
eqivalent to [`filesize`](@ref) when applied to a file, and operates recursively
on directories.
"""
function diskusage(path::String)
    if isfile(path)
        stat(path).blocks * 512 # 512 rather than the blocksize (historical reasons)
    elseif isdir(path)
        try
            subpaths = readdir(path, join=true)
            filter!(!islink, subpaths)
            sum(diskusage, subpaths, init = stat(path).blocks * 512)
        catch err
            if err isa Base.IOError && err.code == -Base.Libc.EACCES # Permission denied
                printstyled(stderr, "[ Warning (diskusage): ", color=Base.warn_color(), bold=true)
                println(stderr, "Couldn't read $path: Permission denied")
                0
            else
                rethrow()
            end
        end
    else
        0
    end
end

const NETWORK_FILESYSTEMS =
    ("9p", "afs", "beegfs", "ceph", "cifs", "coda", "davfs", "ipfs",
     "glusterfs", "lustre", "moosefs", "nfs", "nfs4", "orangefs", "smbfs",
     "sshfs", "vboxsf", "virtiofs")

const SKIP_VOLUMES = ("/dev", "/proc", "/sys", "/usr", "/var", "/boot")

const FUSE_ALLOWED = ("fuse.apfs", "fuse.bindfs", "fuse.cryfs", "fuse.exfat",
                      "fuse.encfs", "fuse.gocryptfs", "fuse.securefs", "fuse.unionfs")

"""
    physicalvolumes() -> Vector{String}

List all accessible physical volumes on the system.
"""
function physicalvolumes()
    volumes = String[]
    nodevfs = nodevfilesystems()
    for mount in readmounts()
        mount.fstype ∈ nodevfs && continue
        mount.fstype ∈ NETWORK_FILESYSTEMS && continue
        startswith(mount.fstype, "fuse.") && mount.fstype ∉ FUSE_ALLOWED && continue
        any(Base.Fix1(startswith, mount.dir), SKIP_VOLUMES) && continue
        ismountedwritable(mount.dir) || continue
        isreadable(mount.dir) || continue
        push!(volumes, mount.dir)
    end
    volumes
end

function nodevfilesystems()
    names = String[]
    for line in eachline("/proc/filesystems")
        fields = split(line)
        length(fields) == 2 || continue
        name, type = fields
        name == "nodev" && push!(names, type)
    end
    names
end

"""
    readmounts() -> Vector{NamedTuple{...}}

Read the `/proc/self/mounts` file and return a list of mount specs.

Each mount spec is represented as a named tuple of `SubString{String}` fields,
with names: `dev`, `dir`, `fstype`, `opts`, `freq`, and `pass`.
"""
function readmounts()
    MountInfo = @NamedTuple{dev::SubString{String}, dir::SubString{String}, fstype::SubString{String}, opts::SubString{String}, freq::SubString{String}, pass::SubString{String}}
    mounts = MountInfo[]
    for line in eachline("/proc/self/mounts")
        fields = split(line)
        length(fields) == 6 || continue
        dev, dir, fstype, opts, freq, pass = fields
        push!(mounts, (; dev, dir, fstype, opts, freq, pass))
    end
    mounts
end

"""
    ismountedwritable(volume::AbstractString)

Check if the volume at `volume` is mounted and writable, according to `statvfs`.
"""
function ismountedwritable(volume::AbstractString)
    st = Ref{NTuple{11, Culong}}()
    if 0 != @ccall statvfs(volume::Cstring, st::Ptr{NTuple{11, Culong}})::Cint
        return false
    end
    st[][10] & 0x1 == 0 # No read-only flag
end

"""
    rfc2396_escape(str::String)

Escape `str` according to [RFC2396](http://www.faqs.org/rfcs/rfc2396.html).
"""
function rfc2396_escape(s::String)
    replace(s, '%' => "%25", # % itself
            # Control characters
            '\0'   => "%0", '\x01'  => "%1", '\x02'  => "%2", '\x03'  => "%3",
            '\x04' => "%4", '\x05'  => "%5", '\x06'  => "%6", '\a'    => "%7",
            '\b'   => "%8", '\t'    => "%9", '\n'    => "%a", '\v'    => "%b",
            '\f'   => "%c", '\r'    => "%d", '\x0e'  => "%e", '\x0f'  => "%f",
            '\x10' => "%10", '\x11' => "%11", '\x12' => "%12", '\x13' => "%13",
            '\x14' => "%14", '\x15' => "%15", '\x16' => "%16", '\x17' => "%17",
            '\x18' => "%18", '\x19' => "%19", '\x1a' => "%1a", '\e'   => "%1b",
            '\x1c' => "%1c", '\x1d' => "%1d", '\x1e' => "%1e", '\x1f' => "%1f",
            '\x7f' => "%7f",
            # Space
            ' ' => "%20",
            # Delims
            '<' => "%3c", '>' => "%3e", '#' => "%23", '"' => "%22",
            # Unwise
            '{' => "%7b", '}' => "%7d", '|' => "%7c", '\\' => "%5c",
            '^' => "%5e", '[' => "%5b", ']' => "%5d", '`' => "%60")
end

"""
    rfc2396_unescape(str::String)

Unescape `str` according to [RFC2396](http://www.faqs.org/rfcs/rfc2396.html).
"""
function rfc2396_unescape(s::String)
    replace(s, "%25" => '%',
            # Control characters
            "%0"  => '\0', "%1"    => '\x01', "%2"  => '\x02', "%3"  => '\x03',
            "%4"  => '\x04', "%5"  => '\x05', "%6"  => '\x06', "%7"  => '\a',
            "%8"  => '\b', "%9"    => '\t', "%a"    => '\n', "%b"    => '\v',
            "%c"  => '\f', "%d"    => '\r', "%e"    => '\x0e', "%f"  => '\x0f',
            "%10" => '\x10', "%11" => '\x11', "%12" => '\x12', "%13" => '\x13',
            "%14" => '\x14', "%15" => '\x15', "%16" => '\x16', "%17" => '\x17',
            "%18" => '\x18', "%19" => '\x19', "%1a" => '\x1a', "%1b" => '\e',
            "%1c" => '\x1c', "%1d" => '\x1d', "%1e" => '\x1e', "%1f" => '\x1f',
            "%7f" => '\x7f',
            # Space
            "%20" => ' ',
            # Delims
            "%3c" => '<', "%3e" => '>', "%23" => '#', "%22" => '"',
            # Unwise
            "%7b" => '{', "%7d" => '}', "%7c" => '|', "%5c" => '\\',
            "%5e" => '^', "%5b" => '[', "%5d" => ']', "%60" => '`')
end

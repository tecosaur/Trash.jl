# SPDX-FileCopyrightText: © 2025 TEC <contact@tecosaur.net>
# SPDX-License-Identifier: MPL-2.0

# References:
# - https://developer.apple.com/documentation/objectivec/objective-c_runtime
# - https://developer.apple.com/documentation/objectivec/1456712-objc_msgsend
# - https://developer.apple.com/documentation/foundation/nsfilemanager/1414306-trashitematurl/
# - https://developer.apple.com/documentation/foundation/nsurl
# - https://developer.apple.com/documentation/foundation/nsurl/1410828-fileurlwithpath/
# - https://developer.apple.com/forums/thread/689800
# - https://discussions.apple.com/thread/253129913
# - https://github.com/sindresorhus/macos-trash/issues/4
# - https://openradar.appspot.com/23153124


module ObjC

const CLASS_CACHE = Dict{String, Ptr{Cvoid}}()
const SELECTOR_CACHE = Dict{String, Ptr{Cvoid}}()

mkclassptr(name::String) = @ccall objc_getClass(name::Ptr{Cchar})::Ptr{Cvoid}
mkselector(name::String) = @ccall sel_registerName(name::Ptr{Cchar})::Ptr{Cvoid}

function class(name::String)
    @something(get(CLASS_CACHE, name, nothing),
               CLASS_CACHE[name] = mkclassptr(name))
end

function selector(name::String)
    @something(get(SELECTOR_CACHE, name, nothing),
               SELECTOR_CACHE[name] = mkselector(name))
end

nsstring(text::String) = @ccall objc_msgSend(class("NSString")::Ptr{Cvoid},
                                             selector("stringWithUTF8String:")::Ptr{Cvoid},
                                             text::Ptr{Cchar})::Ptr{Cvoid}

ns2string(nsstr::Ptr{Cvoid}) =
    unsafe_string(@ccall objc_msgSend(nsstr::Ptr{Cvoid}, selector("UTF8String")::Ptr{Cvoid})::Ptr{Cchar})

nsurl(path::String) = @ccall objc_msgSend(class("NSURL")::Ptr{Cvoid},
                                          selector("fileURLWithPath:")::Ptr{Cvoid},
                                          nsstring(path)::Ptr{Cvoid})::Ptr{Cvoid}

FILE_MANAGER::Ptr{Cvoid} = Ptr{Cvoid}(0)

default_file_manager() =
    @ccall objc_msgSend(class("NSFileManager")::Ptr{Cvoid},
                        selector("defaultManager")::Ptr{Cvoid})::Ptr{Cvoid}

function filemanager()
    global FILE_MANAGER
    if FILE_MANAGER == Ptr{Cvoid}(0)
        FILE_MANAGER = default_file_manager()
    end
    FILE_MANAGER
end

end # ObjC


module DSStoreParser

# References:
# - https://0day.work/parsing-the-ds_store-file-format
# - https://metacpan.org/dist/Mac-Finder-DSStore/view/DSStoreFormat.pod
# - https://github.com/sinistersnare/ds_store
# - https://github.com/dmgbuild/ds_store

const MAGIC_BYTES = Tuple(codeunits("\0\0\0\1Bud1"))

struct DSHeader
    offsets::Vector{UInt32}
    startblock::UInt32
    nrecords::Int
    # toc::Dict{String, UInt32}
    # freelist::Vector{Pair{UInt32, Vector{UInt32}}}
end

struct DSStore{I<:IO}
    io::I
    header::DSHeader
    buf::Vector{UInt8}
end

# DSStore header parsing

function DSStore(io::IO)
    header = DSHeader(io)
    DSStore(io, header, Vector{UInt8}(undef, 4))
end

function DSHeader(io::IO)
    seekstart(io)
    buf = Vector{UInt8}(undef, max(sizeof(UInt32), length(MAGIC_BYTES)))
    hdr = readheader(io, buf)
    isnothing(hdr) && throw(ArgumentError("Invalid DSStore file, missing header"))
    seek(io, hdr.offset + 0x4)
    root = readroot(io, buf)
    isnothing(root) && throw(ArgumentError("Invalid DSStore file, incomplete root block"))
    dsdbaddr = root.offsets[root.dsdb + 0x1]
    dsdboffset = dsdbaddr & 0xe0
    seek(io, dsdboffset + 0x4)
    dsdbincomplete = ArgumentError("Invalid DSStore file, incomplete DSDB block")
    firstblkidx = tryread(UInt32, io, buf)
    isnothing(firstblkidx) && throw(dsdbincomplete)
    _levels = tryread(UInt32, io, buf)
    isnothing(_levels) && throw(dsdbincomplete)
    nrecords = tryread(UInt32, io, buf)
    isnothing(nrecords) && throw(dsdbincomplete)
    _nblocks = tryread(UInt32, io, buf)
    isnothing(_nblocks) && throw(dsdbincomplete)
    confval = tryread(UInt32, io, buf)
    isnothing(confval) && throw(dsdbincomplete)
    confval == 0x00001000 || throw(ArgumentError("Invalid DSStore file, invalid DSDB block"))
    DSHeader(root.offsets, firstblkidx + 0x1, nrecords)
end

function tryread(::Type{T}, io::IO, buf::DenseVector{UInt8}) where {T}
    nb = sizeof(T)
    readbytes!(io, buf, nb) == nb || return
    unsafe_load(Ptr{T}(pointer(buf))) |> ntoh
end

function readheader(io::IO, buf::DenseVector{UInt8})
    readbytes!(io, buf, length(MAGIC_BYTES)) == length(MAGIC_BYTES) || return
    for (b, magic) in zip(buf, MAGIC_BYTES)
        b == magic || return
    end
    offset = tryread(UInt32, io, buf)
    isnothing(offset) && return
    rootsize = tryread(UInt32, io, buf)
    isnothing(rootsize) && return
    offset_check = tryread(UInt32, io, buf)
    isnothing(offset_check) && return
    offset == offset_check || return
    p0 = position(io)
    skip(io, 16)
    position(io) - p0 == 16 || return
    (; offset = offset, rootsize)
end

function readroot(io::IO, buf::DenseVector{UInt8})
    noffsets = tryread(UInt32, io, buf)
    isnothing(noffsets) && return
    skip(io, 4)
    offsets = UInt32[]
    for _ in 1:noffsets
        offset = tryread(UInt32, io, buf)
        isnothing(offset) && return
        push!(offsets, offset)
    end
    skip(io, 4 * mod1(256 - noffsets, 256))
    # toc = readtoc(io, buf)
    # isnothing(toc) && return
    # freelist = readfreelist(io, buf)
    # isnothing(freelist) && return
    # (; offsets, toc, freelist)
    dsdb = readdsdb(io, buf)
    isnothing(dsdb) && return
    (; offsets, dsdb)
end

function readdsdb(io::IO, buf::DenseVector{UInt8})
    ntocs = tryread(UInt32, io, buf)
    isnothing(ntocs) && return
    # toc = Dict{String, UInt32}()
    for _ in 1:ntocs
        namelen = tryread(UInt8, io, buf)
        isnothing(namelen) && return
        readbytes!(io, buf, namelen) == namelen || return
        name = String(buf[1:namelen])
        value = tryread(UInt32, io, buf)
        isnothing(value) && return
        name == "DSDB" && return value
        # toc[name] = value
    end
    # toc
end

function readfreelist(io::IO, buf::DenseVector{UInt8})
    freelist = Pair{UInt32, Vector{UInt32}}[]
    for bucket in 0:31
        bsize = one(UInt32) << bucket
        nboffsets = tryread(UInt32, io, buf)
        isnothing(nboffsets) && return
        boffsets = UInt32[]
        for _ in 1:nboffsets
            offset = tryread(UInt32, io, buf)
            isnothing(offset) && return
            push!(boffsets, offset)
        end
        push!(freelist, bucket => boffsets)
    end
    freelist
end

# DSStore entry reading

struct Record
    filename::String
    kind::Symbol
    dtype::Symbol
    data::Vector{UInt8}
end

Base.eltype(::Type{<:DSStore}) = Record
Base.length(store::DSStore) = store.header.nrecords

const BlockState = @NamedTuple{kind::UInt8, pos::UInt32, nrec::UInt32}

const BKIND_STUB = 0x00
const BKIND_LEAF = 0x01
const BKIND_NODE = 0x02
const BKIND_NREC = 0x03

function Base.iterate(store::DSStore)
    blockstate = [BlockState((BKIND_STUB, store.header.startblock, zero(UInt32)))]
    iterate(store, blockstate)
end

function Base.iterate(store::DSStore, states::Vector{BlockState})
    isempty(states) && return
    # We would need to copy `states` to make this a properly
    # stateful iterator, but I don't really care about that.
    state = last(states)
    if state.kind == BKIND_STUB
        newstate = read_stub(store, states)
        isnothing(newstate) && return
        state = newstate
    end
    # At this point, we know that the block is either a leaf or node
    position(store.io) == state.pos || seek(store.io, state.pos)
    # If the block is a node, we want to jump to the referenced
    # block and read the current record later.
    while state.kind == BKIND_NODE
        states[end] = BlockState((BKIND_NREC, state.pos + 0x4, state.nrec))
        blkidx = @something(tryread(UInt32, store.io, store.buf), return)
        push!(states, BlockState((BKIND_STUB, blkidx + 0x1, zero(UInt32))))
        nextstate = read_stub(store, states)
        isnothing(nextstate) && return
        state = nextstate
    end
    # We must now be at a record
    record = Record(store.io, store.buf)
    # Now we just need to adjust the state so the
    # next record is read correctly.
    remaining = state.nrec - 0x1
    if remaining == 0x0
        pop!(states)
    else
        nextkind = ifelse(state.kind == BKIND_NREC, BKIND_NODE, state.kind)
        states[end] = BlockState((nextkind, position(store.io) % UInt32, remaining))
    end
    record, states
end

function read_stub(store::DSStore, states::Vector{BlockState})
    isempty(states) && return
    idx = last(states).pos
    addr = store.header.offsets[idx]
    offset = addr >> 5 << 5
    size = one(UInt32) << (UInt32(addr) & 0x1f)
    seek(store.io, offset + 0x4)
    next = tryread(UInt32, store.io, store.buf)
    isnothing(next) && return
    nrec = tryread(UInt32, store.io, store.buf)
    isnothing(nrec) && return
    datastart = offset + 0xc
    if iszero(next)
        states[end] = BlockState((BKIND_LEAF, datastart, nrec))
    else
        states[end] = BlockState((BKIND_STUB, next + 0x1, zero(UInt32)))
        push!(states, BlockState((BKIND_NODE, datastart, nrec)))
    end
    last(states)
end

# Record construction

function Record(io::IO, buf::DenseVector{UInt8})
    # Filename
    flen = tryread(UInt32, io, buf)
    isnothing(flen) && throw(ArgumentError("Invalid DSStore record, missing filename length"))
    fnvec = Vector{UInt8}(undef, flen * 2)
    readbytes!(io, fnvec, flen * 2) == flen * 2 ||
        throw(ArgumentError("Invalid DSStore record, missing filename data"))
    filename = transcode(String, map(ntoh, reinterpret(UInt16, fnvec)))
    # Kind
    readbytes!(io, buf, 4) == 4 || throw(ArgumentError("Invalid DSStore record, missing structure id"))
    kind = Symbol(String(buf[1:4]))
    # Data
    dinfo = recdata(io, buf)
    data = Vector{UInt8}(undef, dinfo.nbytes)
    readbytes!(io, data, dinfo.nbytes) == dinfo.nbytes ||
        throw(ArgumentError("Invalid DSStore record, missing data"))
    Record(filename, kind, dinfo.type, data)
end

function recdata(io::IO, buf::DenseVector{UInt8})
    strucid = tryread(UInt32, io, buf)
    isnothing(strucid) && throw(ArgumentError("Invalid DSStore record, missing structure type"))
    type, nbytes = if strucid == name32("long")
        :u32, 4
    elseif strucid == name32("shor")
        :u16, 2
    elseif strucid == name32("bool")
        :bool, 1
    elseif strucid == name32("blob")
        bloblen = tryread(UInt32, io, buf)
        isnothing(bloblen) && throw(ArgumentError("Invalid DSStore record, missing blob length"))
        :blob, Int(bloblen)
    elseif strucid == name32("type")
        :typeid, 4
    elseif strucid == name32("ustr")
        ulen = tryread(UInt32, io, buf)
        isnothing(ulen) && throw(ArgumentError("Invalid DSStore record, missing utf16 length"))
        :utf16str, ulen * 2
    elseif strucid == name32("comp")
        :u64, 8
    elseif strucid == name32("dutc")
        :mactime, 8
    else
        :unknown, 0
    end
    (; type, nbytes)
end

Base.@assume_effects :foldable function name32(name::String)
    ncodeunits(name) == 4 || throw(ArgumentError("Invalid DSStore name, must be 4 bytes"))
    first(reinterpret(UInt32, reverse(codeunits(name))))
end

function value(rec::Record)
    # We only actually care about string values
    if rec.dtype == :utf16str
        value(String, rec)
    end
end

function value(::Type{String}, rec::Record)
    transcode(String, map(ntoh, reinterpret(UInt16, rec.data)))
end

end # DSStore


# Now to actually implement the trash functionality

function trash(path::String; force::Bool=false)
    ispath(path) || (force && return) ||
        throw(Base.IOError("trash($(sprint(show, path))) no such file or directory (ENOENT)", -Base.Libc.ENOENT))
    trashfile_ptr = Ref(Ptr{Cvoid}())
    error_ptr = Ref(Ptr{Cvoid}())
    successflag = @ccall objc_msgSend(
        ObjC.filemanager()::Ptr{Cvoid}, ObjC.selector("trashItemAtURL:resultingItemURL:error:")::Ptr{Cvoid},
        ObjC.nsurl(path)::Ptr{Cvoid}, trashfile_ptr::Ptr{Ptr{Cvoid}}, error_ptr::Ptr{Ptr{Cvoid}})::Bool
    if !successflag
        error_ptr[] == C_NULL &&
            throw(TrashSystemError("trashItemAtURL", "Failed to trash $path for some unknown reason", 0))
        error_code = @ccall objc_msgSend(error_ptr[]::Ptr{Cvoid}, ObjC.selector("code")::Ptr{Cvoid})::Csize_t
        error_domain = @ccall objc_msgSend(error_ptr[]::Ptr{Cvoid}, ObjC.selector("domain")::Ptr{Cvoid})::Ptr{Cvoid}
        throw(TrashSystemError("trashItemAtURL", "Failed to trash $(sprint(show, path)). Darwin error code: $error_code, domain: $(ObjC.ns2string(error_domain))", 0))
    end
    trashfile_nsstring = @ccall objc_msgSend(
        trashfile_ptr[]::Ptr{Cvoid}, ObjC.selector("path")::Ptr{Cvoid})::Ptr{Cvoid}
    trashfile = ObjC.ns2string(trashfile_nsstring)
    TrashFile(trashfile, path, unix2datetime(ctime(trashfile)))
end

function untrash(entry::TrashFile, dest::String=entry.path; force::Bool=false, rm::Bool=false)
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
    dest
end

function list(trashdir::String)
    entries = TrashFile[]
    dsstorefile = joinpath(trashdir, ".DS_Store")
    isfile(dsstorefile) || return entries
    isreadable(dsstorefile) ||
        throw(TrashSystemError("read", "Permission denied to read $dsstorefile, this application has likely not been granted the full disk access permission.", 0))
    dsstore = open(dsstorefile, "r")
    putbackfile = ""
    putbacklocation = ""
    for record in DSStoreParser.DSStore(dsstore)
        if record.kind == :ptbL
            putbackfile = record.filename
            putbacklocation = DSStoreParser.value(String, record)
        elseif record.kind == :ptbN
            record.filename == putbackfile || continue
            trashpath = joinpath(trashdir, record.filename)
            ispath(trashpath) || continue
            oldname = DSStoreParser.value(String, record)
            oldpath = joinpath("/", putbacklocation, oldname)
            dtime = unix2datetime(ctime(trashpath))
            push!(entries, TrashFile(trashpath, oldpath, dtime))
        end
    end
    close(dsstore)
    entries
end

function empty(trashdir::String)
    dsstorefile = joinpath(trashdir, ".DS_Store")
    isfile(dsstorefile) || return
    isreadable(dsstorefile) ||
        throw(TrashSystemError("read", "Permission denied to read $dsstorefile, this application has likely not been granted the full disk access permission.", 0))
    dsstore = open(dsstorefile, "r")
    for record in DSStoreParser.DSStore(dsstore)
        if record.kind == :ptbN
            trashpath = joinpath(trashdir, record.filename)
            ispath(trashpath) || continue
            rm(trashpath, force=true, recursive=true)
        end
    end
    close(dsstore)
    nothing
end

function empty()
    for tdir in trashes()
        iswritable(tdir) || continue
        empty(tdir)
    end
end

const NSTrashDirectory = Clong(102)
const NSUserDomainMask = Clong(1)

function trashdir(path::String)
    error_ptr = Ref(Ptr{Cvoid}())
    dirurl_ptr = @ccall objc_msgSend(
        ObjC.filemanager()::Ptr{Cvoid}, ObjC.selector("URLForDirectory:inDomain:appropriateForURL:create:error:")::Ptr{Cvoid},
        NSTrashDirectory::Clong, NSUserDomainMask::Clong, ObjC.nsurl(path)::Ptr{Cvoid}, false::Cchar, error_ptr::Ptr{Ptr{Cvoid}})::Ptr{Cvoid}
    if dirurl_ptr == C_NULL
        error_ptr[] == C_NULL && throw(Base.IOError("Failed to get trash directory for $path for some unknown reason", 0))
        error_code = @ccall objc_msgSend(error_ptr[]::Ptr{Cvoid}, ObjC.selector("code")::Ptr{Cvoid})::Int
        error_domain = @ccall objc_msgSend(error_ptr[]::Ptr{Cvoid}, ObjC.selector("domain")::Ptr{Cvoid})::Ptr{Cvoid}
        throw(Base.IOError("Failed to get trash directory for $path. Darwin error code: $error_code, domain: $(ObjC.ns2string(error_domain))", 0))
    end
    dirurl_nsstring = @ccall objc_msgSend(
        dirurl_ptr::Ptr{Cvoid}, ObjC.selector("path")::Ptr{Cvoid})::Ptr{Cvoid}
    ObjC.ns2string(dirurl_nsstring)
end

trashdir() = trashdir(homedir())

function localvolumes()
    localkey = ObjC.nsstring("NSURLVolumeIsLocalKey")
    readonlykey = ObjC.nsstring("NSURLVolumeIsReadOnlyKey")
    browsablekey = ObjC.nsstring("NSURLVolumeIsBrowsableKey")
    keyvec = [localkey, readonlykey, browsablekey]
    keysptr = GC.@preserve keyvec @ccall objc_msgSend(
            ObjC.class("NSArray")::Ptr{Cvoid}, ObjC.selector("arrayWithObjects:count:")::Ptr{Cvoid},
            pointer(keyvec)::Ptr{Ptr{Cvoid}}, length(keyvec)::Csize_t)::Ptr{Cvoid}
    @ccall objc_retain(keysptr::Ptr{Cvoid})::Ptr{Cvoid}
    mountedsel = ObjC.selector("mountedVolumeURLsIncludingResourceValuesForKeys:options:")
    vols = @ccall objc_msgSend(ObjC.filemanager()::Ptr{Cvoid}, mountedsel::Ptr{Cvoid},
                               keysptr::Ptr{Cvoid}, 1::Culong)::Ptr{Cvoid}
    @ccall objc_retain(vols::Ptr{Cvoid})::Ptr{Cvoid}
    nvols = if vols != C_NULL
        @ccall objc_msgSend(vols::Ptr{Cvoid}, ObjC.selector("count")::Ptr{Cvoid})::Csize_t
    else Csize_t(0) end
    volnames = String[]
    for i in 1:nvols
        volurl = @ccall objc_msgSend(vols::Ptr{Cvoid}, ObjC.selector("objectAtIndex:")::Ptr{Cvoid}, (i - 1)::Csize_t)::Ptr{Cvoid}
        volkeys = @ccall objc_msgSend(volurl::Ptr{Cvoid}, ObjC.selector("resourceValuesForKeys:error:")::Ptr{Cvoid}, keysptr::Ptr{Cvoid}, C_NULL::Ptr{Cvoid})::Ptr{Cvoid}
        volkeys == C_NULL && continue
        vollocal = @ccall objc_msgSend(volkeys::Ptr{Cvoid}, ObjC.selector("objectForKey:")::Ptr{Cvoid}, localkey::Ptr{Cvoid})::Ptr{Cvoid}
        islocal = @ccall objc_msgSend(vollocal::Ptr{Cvoid}, ObjC.selector("boolValue")::Ptr{Cvoid})::Bool
        islocal || continue
        volreadonly = @ccall objc_msgSend(volkeys::Ptr{Cvoid}, ObjC.selector("objectForKey:")::Ptr{Cvoid}, readonlykey::Ptr{Cvoid})::Ptr{Cvoid}
        isreadonly = @ccall objc_msgSend(volreadonly::Ptr{Cvoid}, ObjC.selector("boolValue")::Ptr{Cvoid})::Bool
        !isreadonly || continue
        volbrowsable = @ccall objc_msgSend(volkeys::Ptr{Cvoid}, ObjC.selector("objectForKey:")::Ptr{Cvoid}, browsablekey::Ptr{Cvoid})::Ptr{Cvoid}
        isbrowsable = @ccall objc_msgSend(volbrowsable::Ptr{Cvoid}, ObjC.selector("boolValue")::Ptr{Cvoid})::Bool
        isbrowsable || continue
        volname = @ccall objc_msgSend(volurl::Ptr{Cvoid}, ObjC.selector("path")::Ptr{Cvoid})::Ptr{Cvoid}
        push!(volnames, ObjC.ns2string(volname))
    end
    @ccall objc_release(keysptr::Ptr{Cvoid})::Ptr{Cvoid}
    @ccall objc_release(vols::Ptr{Cvoid})::Ptr{Cvoid}
    volnames
end

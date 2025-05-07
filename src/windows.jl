# SPDX-FileCopyrightText: © 2025 TEC <contact@tecosaur.net>
# SPDX-License-Identifier: MPL-2.0

# Types and constants for Windows COM and Shell API

struct WindowsGUID
    d1::UInt32
    d2::UInt16
    d3::UInt16
    d4::NTuple{8, UInt8}
end

# Common Windows types
const HRESULT = Clong
const DWORD = Culong
const LPVOID = Ptr{Cvoid}
const LPCWSTR = Ptr{UInt16} # Pointer to constant wide string
const LPWSTR = Ptr{UInt16}  # Pointer to non-constant wide string
const REFIID = Ptr{WindowsGUID} # Pointer to Interface ID
const REFCLSID = Ptr{WindowsGUID} # Pointer to Class ID

const S_OK = 0 % HRESULT
const E_NOINTERFACE = 0x80004002 % HRESULT
const E_FAIL = 0x80004005 % HRESULT
const E_ABORT = 0x80004004 % HRESULT # Often returned by sink to stop
const RPC_E_CHANGED_MODE = 0x80010106 % HRESULT # CoInitializeEx failed

# COM Initialization Flags
const COINIT_APARTMENTTHREADED = 0x2
const COINIT_DISABLE_OLE1DDE = 0x4

# Class Context Flags
const CLSCTX_INPROC_SERVER = 0x1
const CLSCTX_LOCAL_SERVER = 0x4
const CLSCTX_REMOTE_SERVER = 0x10
const CLSCTX_ALL = CLSCTX_INPROC_SERVER | CLSCTX_LOCAL_SERVER | CLSCTX_REMOTE_SERVER

# Important GUID Constants
const CLSID_FileOperation = WindowsGUID(0x3ad05575, 0x8857, 0x4850, (0x92, 0x77, 0x11, 0xb8, 0x5b, 0xdb, 0x8e, 0x09))
const IID_IUnknown = WindowsGUID(0x00000000, 0x0000, 0x0000, (0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46))
const IID_IFileOperation = WindowsGUID(0x947aab5f, 0x0a5c, 0x4c13, (0xb4, 0xd6, 0x4b, 0xf7, 0x83, 0x6f, 0xc9, 0xf8))
const IID_IShellItem = WindowsGUID(0x43826d1e, 0xe718, 0x42ee, (0xbc, 0x55, 0xa1, 0xe2, 0x61, 0xc3, 0x7b, 0xfe))
const IID_IFileOperationProgressSink = WindowsGUID(0x04b0f1a7, 0x9490, 0x44bc, (0x96, 0xe1, 0x42, 0x96, 0xa3, 0x12, 0x52, 0xe2))

# SHFileOperation Flags
const FOF_ALLOWUNDO          = 0x0040
const FOF_NOCONFIRMATION     = 0x0010
const FOF_SILENT             = 0x0004
const FOF_NOERRORUI          = 0x0400

# SIGDN Constants for GetDisplayName
const SIGDN_FILESYSPATH = 0x80058000 # Get file system path (LPWSTR)

# SHEmptyRecycleBin Flags
const SHERB_NOCONFIRMATION = 0x00000001 % DWORD
const SHERB_NOPROGRESSUI   = 0x00000002 % DWORD
const SHERB_NOSOUND        = 0x00000004 % DWORD

# Interface singletons
struct IUnknown end
struct IFileOperation end
struct IShellItem end

# COM Interface VTable Definitions

struct IUnknownVtbl
    QueryInterface::Ptr{Cvoid}
    AddRef::Ptr{Cvoid}
    Release::Ptr{Cvoid}
end

struct IShellItemVtbl
    QueryInterface::Ptr{Cvoid}
    AddRef::Ptr{Cvoid}
    Release::Ptr{Cvoid}
    BindToHandler::Ptr{Cvoid}
    GetParent::Ptr{Cvoid}
    GetDisplayName::Ptr{Cvoid}
    GetAttributes::Ptr{Cvoid}
    Compare::Ptr{Cvoid}
end

struct IFileOperationVtbl
    QueryInterface::Ptr{Cvoid}
    AddRef::Ptr{Cvoid}
    Release::Ptr{Cvoid}
    Advise::Ptr{Cvoid}
    Unadvise::Ptr{Cvoid}
    SetOperationFlags::Ptr{Cvoid}
    SetProgressMessage::Ptr{Cvoid}
    SetProgressDialog::Ptr{Cvoid}
    SetProperties::Ptr{Cvoid}
    SetOwnerWindow::Ptr{Cvoid}
    ApplyPropertiesToItem::Ptr{Cvoid}
    ApplyPropertiesToItems::Ptr{Cvoid}
    RenameItem::Ptr{Cvoid}
    RenameItems::Ptr{Cvoid}
    MoveItem::Ptr{Cvoid}
    MoveItems::Ptr{Cvoid}
    CopyItem::Ptr{Cvoid}
    CopyItems::Ptr{Cvoid}
    DeleteItem::Ptr{Cvoid}
    DeleteItems::Ptr{Cvoid}
    NewItem::Ptr{Cvoid}
    PerformOperations::Ptr{Cvoid}
    GetAnyOperationsAborted::Ptr{Cvoid}
end

struct IFileOperationProgressSinkVtbl
    QueryInterface::Ptr{Cvoid}
    AddRef::Ptr{Cvoid}
    Release::Ptr{Cvoid}
    StartOperations::Ptr{Cvoid}
    FinishOperations::Ptr{Cvoid}
    PreRenameItem::Ptr{Cvoid}
    PostRenameItem::Ptr{Cvoid}
    PreMoveItem::Ptr{Cvoid}
    PostMoveItem::Ptr{Cvoid}
    PreCopyItem::Ptr{Cvoid}
    PostCopyItem::Ptr{Cvoid}
    PreDeleteItem::Ptr{Cvoid}
    PostDeleteItem::Ptr{Cvoid} # The one we care about
    PreNewItem::Ptr{Cvoid}
    PostNewItem::Ptr{Cvoid}
    UpdateProgress::Ptr{Cvoid}
    ResetTimer::Ptr{Cvoid}
    PauseTimer::Ptr{Cvoid}
    ResumeTimer::Ptr{Cvoid}
end

# Helper functions

isfailed(res::HRESULT) = res < 0
issuccess(res::HRESULT) = res >= 0

utf16nul(s::String) = push!(transcode(UInt16, s), zero(UInt16))

function unsafe_utf16string(ptr::Ptr{UInt16})
    ptr == C_NULL && return ""
    len = 0
    while unsafe_load(ptr, len + 1) != 0
        len += 1
    end
    len == 0 && return ""
    buf = Vector{UInt16}(undef, len)
    unsafe_copyto!(pointer(buf), ptr, len)
    transcode(String, buf)
end

function CoTaskMemFree(ptr::LPVOID)
    ptr == C_NULL && return
    ccall((:CoTaskMemFree, "ole32"), stdcall, Cvoid, (LPVOID,), ptr)
end

CoTaskMemFree(ptr::Ptr) = CoTaskMemFree(LPVOID(ptr))

function release(obj_ptr::Ptr{<:Any})
    if obj_ptr != C_NULL
        unknown_ptr = Ptr{IUnknown}(obj_ptr)
        vtbl_ptr = unsafe_load(Ptr{Ptr{IUnknownVtbl}}(unknown_ptr))
        vtbl = unsafe_load(vtbl_ptr)
        # Call Release through the vtable
        ccall(vtbl.Release, stdcall, Culong, (Ptr{IUnknown},), unknown_ptr)
    end
    nothing
end

# Julia Implementation of `IFileOperationProgressSink`
mutable struct TrashProgressSink
    lpVtbl::Ptr{IFileOperationProgressSinkVtbl}
    refcount::Culong
    priorpath::String
    recyclepath::String
    error::Union{TrashSystemError, Nothing}
end

TrashProgressSink() =
    TrashProgressSink(pointer_from_objref(vtable_sink()), 1, "", "", nothing)


# @ccallable Functions for the VTable
#
# These functions are the actual implementations called by COM.
# They must match the expected signature (stdcall, types).

function sink_QueryInterface(fileop::Ptr{TrashProgressSink}, riid::REFIID, ppvObject::Ptr{Ptr{Cvoid}})::HRESULT
    iid = unsafe_load(riid)
    if iid == IID_IUnknown || iid == IID_IFileOperationProgressSink
        # If requesting known interface, AddRef and return pointer
        ccall(VTABLE_SINK[].AddRef, stdcall, Culong, (Ptr{TrashProgressSink},), fileop)
        unsafe_store!(ppvObject, fileop)
        S_OK
    else # Unknown interface requested
        unsafe_store!(ppvObject, C_NULL)
        E_NOINTERFACE
    end
end

function sink_AddRef(fileop::Ptr{TrashProgressSink})::Culong
    sink = Base.unsafe_pointer_to_objref(fileop)
    sink.refcount += 1
end

function sink_Release(fileop::Ptr{TrashProgressSink})::Culong
    sink = Base.unsafe_pointer_to_objref(fileop)
    sink.refcount -= 1
end

function sink_PostDeleteItem(fileop::Ptr{TrashProgressSink}, dwFlags::DWORD, psiItem::Ptr{IShellItem}, hrDelete::HRESULT, psiNewlyCreated::Ptr{IShellItem})::HRESULT
    sink = Base.unsafe_pointer_to_objref(fileop)
    issuccess(hrDelete) || return S_OK
    # Get Original Path
    if psiItem != C_NULL
        vtbl_ptr_orig = unsafe_load(Ptr{Ptr{IShellItemVtbl}}(psiItem))
        vtbl_orig = unsafe_load(vtbl_ptr_orig)
        priorpath_ptr = Ref(LPWSTR(C_NULL))
        hr_orig = ccall(vtbl_orig.GetDisplayName, stdcall, HRESULT,
                        (Ptr{IShellItem}, DWORD, Ptr{LPWSTR}),
                        psiItem, SIGDN_FILESYSPATH, priorpath_ptr)
        if issuccess(hr_orig) && priorpath_ptr[] != C_NULL
            sink.priorpath = unsafe_utf16string(priorpath_ptr[]) # Use safe helper
        else
            sink.error = TrashSystemError("IFileOperationProgressSink.GetDisplayName", "failed to get original path display name", hr_orig)
        end
        CoTaskMemFree(priorpath_ptr[])
    else
        sink.error = TrashSystemError("IFileOperationProgressSink.PostDeleteItem", "Original IShellItem pointer was NULL.")
    end
    # Get Recycle Bin Path
    if psiNewlyCreated != C_NULL
        vtbl_ptr_new = unsafe_load(Ptr{Ptr{IShellItemVtbl}}(psiNewlyCreated))
        vtbl_new = unsafe_load(vtbl_ptr_new)
        recyclepath_ptr = Ref(LPWSTR(C_NULL))
        hr_new = ccall(vtbl_new.GetDisplayName, stdcall, HRESULT,
                        (Ptr{IShellItem}, DWORD, Ptr{LPWSTR}),
                        psiNewlyCreated, SIGDN_FILESYSPATH, recyclepath_ptr)
        if issuccess(hr_new) && recyclepath_ptr[] != C_NULL
            sink.recyclepath = unsafe_utf16string(recyclepath_ptr[])
        else
            sink.error = TrashSystemError("IFileOperationProgressSink.GetDisplayName", "failed to get recycle path display name", hr_new)
        end
        CoTaskMemFree(recyclepath_ptr[])
    else
        # This is expected if the delete operation failed or didn't recycle (e.g., Shift+Delete)
        sink.error = TrashSystemError("IFileOperationProgressSink.PostDeleteItem", "newly created IShellItem pointer was NULL; item might not have been recycled?", hrDelete)
    end
    S_OK
end

# Stub Implementations for other Sink methods (@ccallable)
function sink_StartOperations(this::Ptr{TrashProgressSink})::HRESULT S_OK end
function sink_FinishOperations(this::Ptr{TrashProgressSink}, hrResult::HRESULT)::HRESULT S_OK end
function sink_PreRenameItem(this::Ptr{TrashProgressSink}, dwFlags::DWORD, psiItem::Ptr{IShellItem}, pszNewName::LPCWSTR)::HRESULT S_OK end
function sink_PostRenameItem(this::Ptr{TrashProgressSink}, dwFlags::DWORD, psiItem::Ptr{IShellItem}, pszNewName::LPCWSTR, hrRename::HRESULT, psiNewlyCreated::Ptr{IShellItem})::HRESULT S_OK end
function sink_PreMoveItem(this::Ptr{TrashProgressSink}, dwFlags::DWORD, psiItem::Ptr{IShellItem}, psiDestinationFolder::Ptr{IShellItem}, pszNewName::LPCWSTR)::HRESULT S_OK end
function sink_PostMoveItem(this::Ptr{TrashProgressSink}, dwFlags::DWORD, psiItem::Ptr{IShellItem}, psiDestinationFolder::Ptr{IShellItem}, pszNewName::LPCWSTR, hrMove::HRESULT, psiNewlyCreated::Ptr{IShellItem})::HRESULT S_OK end
function sink_PreCopyItem(this::Ptr{TrashProgressSink}, dwFlags::DWORD, psiItem::Ptr{IShellItem}, psiDestinationFolder::Ptr{IShellItem}, pszNewName::LPCWSTR)::HRESULT S_OK end
function sink_PostCopyItem(this::Ptr{TrashProgressSink}, dwFlags::DWORD, psiItem::Ptr{IShellItem}, psiDestinationFolder::Ptr{IShellItem}, pszNewName::LPCWSTR, hrCopy::HRESULT, psiNewlyCreated::Ptr{IShellItem})::HRESULT S_OK end
function sink_PreDeleteItem(this::Ptr{TrashProgressSink}, dwFlags::DWORD, psiItem::Ptr{IShellItem})::HRESULT S_OK end
function sink_PreNewItem(this::Ptr{TrashProgressSink}, dwFlags::DWORD, psiDestinationFolder::Ptr{IShellItem}, pszNewName::LPCWSTR)::HRESULT S_OK end
function sink_PostNewItem(this::Ptr{TrashProgressSink}, dwFlags::DWORD, psiDestinationFolder::Ptr{IShellItem}, pszNewName::LPCWSTR, pszTemplateName::LPCWSTR, dwTemplateFlags::DWORD, hrNew::HRESULT, psiNewItem::Ptr{IShellItem})::HRESULT S_OK end
function sink_UpdateProgress(this::Ptr{TrashProgressSink}, iWorkTotal::Cuint, iWorkSoFar::Cuint)::HRESULT S_OK end
function sink_ResetTimer(this::Ptr{TrashProgressSink})::HRESULT S_OK end
function sink_PauseTimer(this::Ptr{TrashProgressSink})::HRESULT S_OK end
function sink_ResumeTimer(this::Ptr{TrashProgressSink})::HRESULT S_OK end

const VTABLE_SINK = Ref{IFileOperationProgressSinkVtbl}() # Use Ref for global constant struct

function vtable_sink()
    VTABLE_SINK[].QueryInterface != C_NULL && return VTABLE_SINK
    VTABLE_SINK[] = IFileOperationProgressSinkVtbl(
        @cfunction(sink_QueryInterface, HRESULT, (Ptr{TrashProgressSink}, REFIID, Ptr{Ptr{Cvoid}})),
        @cfunction(sink_AddRef, Culong, (Ptr{TrashProgressSink},)),
        @cfunction(sink_Release, Culong, (Ptr{TrashProgressSink},)),
        @cfunction(sink_StartOperations, HRESULT, (Ptr{TrashProgressSink},)),
        @cfunction(sink_FinishOperations, HRESULT, (Ptr{TrashProgressSink}, HRESULT)),
        @cfunction(sink_PreRenameItem, HRESULT, (Ptr{TrashProgressSink}, DWORD, Ptr{IShellItem}, LPCWSTR)),
        @cfunction(sink_PostRenameItem, HRESULT, (Ptr{TrashProgressSink}, DWORD, Ptr{IShellItem}, LPCWSTR, HRESULT, Ptr{IShellItem})),
        @cfunction(sink_PreMoveItem, HRESULT, (Ptr{TrashProgressSink}, DWORD, Ptr{IShellItem}, Ptr{IShellItem}, LPCWSTR)),
        @cfunction(sink_PostMoveItem, HRESULT, (Ptr{TrashProgressSink}, DWORD, Ptr{IShellItem}, Ptr{IShellItem}, LPCWSTR, HRESULT, Ptr{IShellItem})),
        @cfunction(sink_PreCopyItem, HRESULT, (Ptr{TrashProgressSink}, DWORD, Ptr{IShellItem}, Ptr{IShellItem}, LPCWSTR)),
        @cfunction(sink_PostCopyItem, HRESULT, (Ptr{TrashProgressSink}, DWORD, Ptr{IShellItem}, Ptr{IShellItem}, LPCWSTR, HRESULT, Ptr{IShellItem})),
        @cfunction(sink_PreDeleteItem, HRESULT, (Ptr{TrashProgressSink}, DWORD, Ptr{IShellItem})),
        @cfunction(sink_PostDeleteItem, HRESULT, (Ptr{TrashProgressSink}, DWORD, Ptr{IShellItem}, HRESULT, Ptr{IShellItem})),
        @cfunction(sink_PreNewItem, HRESULT, (Ptr{TrashProgressSink}, DWORD, Ptr{IShellItem}, LPCWSTR)),
        @cfunction(sink_PostNewItem, HRESULT, (Ptr{TrashProgressSink}, DWORD, Ptr{IShellItem}, LPCWSTR, LPCWSTR, DWORD, HRESULT, Ptr{IShellItem})),
        @cfunction(sink_UpdateProgress, HRESULT, (Ptr{TrashProgressSink}, Cuint, Cuint)),
        @cfunction(sink_ResetTimer, HRESULT, (Ptr{TrashProgressSink},)),
        @cfunction(sink_PauseTimer, HRESULT, (Ptr{TrashProgressSink},)),
        @cfunction(sink_ResumeTimer, HRESULT, (Ptr{TrashProgressSink},)))
    VTABLE_SINK
end


# Current user SID

const HANDLE = Ptr{Cvoid}
const PHANDLE = Ptr{HANDLE}
const PSID = Ptr{Cvoid} # Pointer to a SID structure
const PLPWSTR = Ptr{LPWSTR} # Pointer to a pointer to a wide string

# Token Access Rights
const TOKEN_QUERY = 0x0008

# TOKEN_INFORMATION_CLASS Enum value
const TokenUser = 1 # Retrieves TOKEN_USER structure

# Well-known error codes
const ERROR_INSUFFICIENT_BUFFER = 122 % DWORD

function usersid()
    # 1. Get handle to current process
    proc_handle = ccall((:GetCurrentProcess, "kernel32"), stdcall, HANDLE, ())
    # 2. Open the process token
    token_handle = Ref{HANDLE}(C_NULL)
    success = ccall((:OpenProcessToken, "advapi32"), stdcall, Cint,
                    (HANDLE, DWORD, PHANDLE),
                    proc_handle, TOKEN_QUERY, token_handle)
    success == 0 && throw(TrashSystemError("OpenProcessToken"))
    # 3. Get Token Information (first call for size)
    required_size = Ref{DWORD}(0)
    # Call with NULL buffer to get required size
    ccall((:GetTokenInformation, "advapi32"), stdcall, Cint,
            (HANDLE, Cint, LPVOID, DWORD, Ptr{DWORD}),
            token_handle[], TokenUser, C_NULL, 0, required_size)
    # Expect ERROR_INSUFFICIENT_BUFFER
    err_code = Base.Libc.GetLastError()
    (err_code == ERROR_INSUFFICIENT_BUFFER && required_size[] != 0) ||
        ccall((:CloseHandle, "kernel32"), stdcall, Cint, (HANDLE,), token_handle[])
    if err_code != ERROR_INSUFFICIENT_BUFFER
        throw(TrashSystemError("GetTokenInformation", "failed unexpectedly", err_code))
    end
    required_size[] == 0 &&
        throw(TrashSystemError("GetTokenInformation", "reported zero required size"))
    # 4. Allocate buffer and get Token Information (second call for data)
    token_info_buffer = Vector{UInt8}(undef, required_size[])
    bytes_returned = Ref{DWORD}(0) # Can reuse required_size, but this is clearer
    success = ccall((:GetTokenInformation, "advapi32"), stdcall, Cint,
                    (HANDLE, Cint, LPVOID, DWORD, Ptr{DWORD}),
                    token_handle[], TokenUser, pointer(token_info_buffer), required_size[], bytes_returned)
    ccall((:CloseHandle, "kernel32"), stdcall, Cint, (HANDLE,), token_handle[])
    success == 0 && throw(TrashSystemError("GetTokenInformation"))
    # 5. Extract the PSID from the TOKEN_USER structure
    # The TOKEN_USER struct starts with SID_AND_ATTRIBUTES, which starts with the PSID.
    # So, the PSID is effectively at the start of the buffer. We need to read the pointer.
    # We need Ptr{PSID} which is Ptr{Ptr{Cvoid}}
    psid_ptr = unsafe_load(convert(Ptr{PSID}, pointer(token_info_buffer)))
    psid_ptr == C_NULL && throw(TrashSystemError("", "Extracted PSID from token information is NULL."))
    # 6. Convert SID to String
    sid_ptr = Ref{LPWSTR}(C_NULL)
    success = ccall((:ConvertSidToStringSidW, "advapi32"), stdcall, Cint,
                    (PSID, PLPWSTR),
                    psid_ptr, sid_ptr)
    success == 0 && throw(TrashSystemError("ConvertSidToStringSidW"))
    sid = unsafe_utf16string(sid_ptr[])
    ccall((:LocalFree, "kernel32"), stdcall, Ptr{Cvoid}, (Ptr{Cvoid},), sid_ptr[])
    sid
end


# Implementation of the trash API

function trash(path::String; force::Bool=false)::Union{TrashFile, Nothing}
    path = abspath(path)
    ispath(path) || (force && return) ||
        throw(Base.IOError("trash($(sprint(show, path))) no such file or directory (ENOENT)", -Base.Libc.ENOENT))
    sink = TrashProgressSink()
    # 1. Initialize COM
    status = ccall((:CoInitializeEx, "ole32"), stdcall, HRESULT, (LPVOID, DWORD), C_NULL, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE)
    isfailed(status) && status != RPC_E_CHANGED_MODE &&
        throw(TrashSystemError("CoInitializeEx", nothing, status))
    try
        # Keep the sink object alive for the duration of the COM calls
        GC.@preserve sink begin
            # 2. Create IFileOperation instance
            file_op_indirect = Ref(Ptr{IFileOperation}(C_NULL))
            status = ccall((:CoCreateInstance, "ole32"), stdcall, HRESULT,
                    (REFCLSID, Ptr{IUnknown}, DWORD, REFIID, Ptr{Ptr{IFileOperation}}),
                    Ref(CLSID_FileOperation), C_NULL, CLSCTX_ALL, Ref(IID_IFileOperation), file_op_indirect)
            isfailed(status) && throw(TrashSystemError("CoCreateInstance", nothing, status))
            file_op_ptr = file_op_indirect[]
            try
                # Get IFileOperation vtable pointer
                vtbl_op_ptr = unsafe_load(Ptr{Ptr{IFileOperationVtbl}}(file_op_ptr))
                vtbl_op = unsafe_load(vtbl_op_ptr)
                # 3. Set Operation Flags
                op_flags = FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_NOERRORUI | FOF_SILENT
                status = ccall(vtbl_op.SetOperationFlags, stdcall, HRESULT, (Ptr{IFileOperation}, DWORD), file_op_ptr, op_flags)
                isfailed(status) && throw(TrashSystemError("IFileOperation::SetOperationFlags", nothing, status))
                # 4. Register the Sink
    advise_cookie = Ref{DWORD}(0)
                status = ccall(vtbl_op.Advise, stdcall, HRESULT,
                        (Ptr{IFileOperation}, Ptr{TrashProgressSink}, Ptr{DWORD}),
                        file_op_ptr, pointer_from_objref(sink), advise_cookie) # Pass pointer to Julia object
                isfailed(status) && throw(TrashSystemError("IFileOperation::Advise", nothing, status))
                try
                    # 5. Create IShellItem from path
                    item_ref = Ref(Ptr{IShellItem}(C_NULL))
                    status = ccall((:SHCreateItemFromParsingName, "shell32"), stdcall, HRESULT,
                            (LPCWSTR, Ptr{Cvoid}, REFIID, Ptr{Ptr{IShellItem}}),
                            pointer(utf16nul(path)), C_NULL, Ref(IID_IShellItem), item_ref)
                    isfailed(status) && throw(TrashSystemError("SHCreateItemFromParsingName", nothing, status))
                    item_ptr = item_ref[]
                    # 6. Queue the Delete operation
                    status = ccall(vtbl_op.DeleteItem, stdcall, HRESULT,
                            (Ptr{IFileOperation}, Ptr{IShellItem}, Ptr{Cvoid}),
                            file_op_ptr, item_ptr, C_NULL) # 3rd arg is context for sink, NULL ok
                    isfailed(status) && throw(TrashSystemError("IFileOperation::DeleteItem", nothing, status))
                    # 7. Perform the operation (Triggers sink_PostDeleteItem)
                    status = ccall(vtbl_op.PerformOperations, stdcall, HRESULT, (Ptr{IFileOperation},), file_op_ptr)
                    isfailed(status) && throw(TrashSystemError("IFileOperation::PerformOperations", nothing, status))
                    release(item_ptr) # Release IShellItem
                finally
                    # 9. Unadvise the Sink
                    if advise_cookie[] != 0
                         hr_unadvise = ccall(vtbl_op.Unadvise, stdcall, HRESULT, (Ptr{IFileOperation}, DWORD), file_op_ptr, advise_cookie[])
                         isfailed(hr_unadvise) && throw(TrashSystemError("IFileOperation::Unadvise", nothing, status))
                    end
                end
            finally
                release(file_op_ptr) # Release IFileOperation
            end
        end # GC.@preserve
    finally
        # 10. Uninitialize COM
        ccall((:CoUninitialize, "ole32"), stdcall, Cvoid, ())
    end
    isnothing(sink.error) || throw(sink.error) # Rethrow any error captured in the sink
    isempty(sink.recyclepath) &&
        throw(TrashSystemError("PostDeleteItem", "Failed to capture paths, recycle path is NULL. Item might not have been recycled?"))
    dtime = let mfile = metadatafile(sink.recyclepath)
        if !isnothing(mfile)
            mdata = parsemetadata(mfile)
            if !isnothing(mdata)
                mdata.dtime
            else
                now(UTC)
            end
        else
            now(UTC)
        end
    end
    TrashFile(sink.recyclepath, path, dtime)
end

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
    mv(entry.trashfile, dest)
    try # Cleanup metadata on a best-effort basis
        mdata = metadatafile(entry)
        !isnothing(mdata) && Base.rm(mdata)
    catch end
    dest
end

function trashdir(path::String)
    drive, _ = splitdrive(abspath(path))
    # Using `joinpath` will drop the drive component
    "$drive\\\$Recycle.Bin\\$(usersid())"
end

trashdir() = trashdir(homedir())

function list(trashdir::String)
    entries = TrashFile[]
    try isdir(trashdir) catch; false end || return entries
    for path in readdir(trashdir, join=true)
        startswith(basename(path), "\$R") || continue
        mdatafile = metadatafile(path)
        isnothing(mdatafile) && continue
        isfile(mdatafile) || continue
        info = parsemetadata(mdatafile)
        isnothing(info) && continue
        push!(entries, TrashFile(path, info.filename, info.dtime))
    end
    entries
end

function empty(trashdir::String)
    rm(trashdir, force=true, recursive=true)
end

function empty()
    flags = SHERB_NOCONFIRMATION | SHERB_NOPROGRESSUI | SHERB_NOSOUND
    hr = ccall((:SHEmptyRecycleBinW, "shell32"), stdcall, HRESULT,
               (Ptr{Cvoid}, LPCWSTR, DWORD), C_NULL, C_NULL, flags)
    if isfailed(hr)
        throw(TrashSystemError("SHEmptyRecycleBinW", nothing, hr))
    end
end

function localvolumes()
    mask = ccall((:GetLogicalDrives, "kernel32"), stdcall, UInt32, ())
    drives = String[]
    for (i, char) in zip(0:25, 'A':'Z')
        mask & (1 << i) != 0 || continue
        drive = char * ":\\"
        dtype = ccall((:GetDriveTypeW, "kernel32"), stdcall, UInt32, (Ptr{UInt16},), pointer(utf16nul(drive)))
        dtype ∈ (2, 3) && push!(drives, drive) # 2 = removable, 3 = fixed
    end
    drives
end


# Helper functions

"""
    metadatafile(trashfile::String) -> String
    metadatafile(trashfile::TrashFile) -> String

Get the metadata file name for a given trash file.
"""
function metadatafile(trashfile::String)
    nr = count("\$R", trashfile)
    nr == 0 && throw(ArgumentError("Invalid trash file name: $trashfile"))
    infofile = if nr == 1
        replace(trashfile, "\$R" => "\$I")
    else
        tr = findlast("\$R", trashfile)::UnitRange{Int}
        trashfile[1:first(tr)-1] * "\$I" * trashfile[last(tr)+1:end]
    end
    isfile(infofile) || return
    infofile
end

metadatafile(entry::TrashFile) = metadatafile(entry.trashfile)

const NT_TICKS_PER_SECOND = 10^7
const NT_EPOCH_OFFSET_SECONDS = 60 * 60 * 24 * (365 * (1970 - 1601) + 89)
const NT_EPOCH_OFFSET_TICKS = NT_EPOCH_OFFSET_SECONDS * NT_TICKS_PER_SECOND

"""
    nt2datetime(wintime::Integer) -> DateTime

Convert a Windows NT time (in 100-nanosecond intervals since January 1, 1601) to a DateTime.
"""
function nt2datetime(wintime::Integer)
    msec = (wintime - NT_EPOCH_OFFSET_TICKS) ÷ 10000
    unixmsec = Millisecond(Dates.UNIXEPOCH + msec)
    DateTime(Dates.UTInstant(unixmsec))
end

"""
    parsemetadata(file::String) -> (;filename::String, filesize::Int, dtime::DateTime)

Parse the metadata file for a given trash file.

The metadata file is expected to be in the format used by Windows Recycle Bin
on Windows Vista and later (handling both the Vista to Windows 8.1 format
and the Windows 10+ format).
"""
function parsemetadata(file::String)
    isfile(file) || return
    open(file) do io
        filesize(io) < 28 && return
        version = read(io, UInt64)
        if isnothing(version)
            return
        elseif version == 1 # Vista to Win8.1
            filesize(io) == 544 || return
            fsize = read(io, UInt64)
            dtimewin = read(io, UInt64)
            utf16 = reinterpret(UInt16, read(io))
            fname = transcode(String, utf16[1:something(findfirst(iszero, utf16), length(utf16)+1)-1])
            (; filename = fname, filesize = fsize, dtime = nt2datetime(dtimewin))
        elseif version == 2 # Win10+
            fsize = read(io, UInt64)
            dtimewin = read(io, UInt64)
            fnamelen = read(io, UInt32)
            fname = transcode(String, reinterpret(UInt16, read(io, 2 * fnamelen - 2)))
            (; filename = fname, filesize = fsize, dtime = nt2datetime(dtimewin))
        end
    end
end

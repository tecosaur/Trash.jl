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

classptr(name::String) = @ccall objc_getClass(name::Ptr{Cchar})::Ptr{Cvoid}
selector(name::String) = @ccall sel_registerName(name::Ptr{Cchar})::Ptr{Cvoid}
nsstring(text::String) = @ccall objc_msgSend(classptr("NSString")::Ptr{Cvoid},
                                             selector("stringWithUTF8String:")::Ptr{Cvoid},
                                             text::Ptr{Cchar})::Ptr{Cvoid}

ns2string(nsstr::Ptr{Cvoid}) =
    unsafe_string(@ccall objc_msgSend(nsstr::Ptr{Cvoid}, selector("UTF8String")::Ptr{Cvoid})::Ptr{Cchar})

nsurl(path::String) = @ccall objc_msgSend(classptr("NSURL")::Ptr{Cvoid},
                                          selector("fileURLWithPath:")::Ptr{Cvoid},
                                          nsstring(path)::Ptr{Cvoid})::Ptr{Cvoid}

FILE_MANAGER::Ptr{Cvoid} = Ptr{Cvoid}(0)

default_file_manager() =
    @ccall objc_msgSend(classptr("NSFileManager")::Ptr{Cvoid},
                        selector("defaultManager")::Ptr{Cvoid})::Ptr{Cvoid}

function filemanager()
    global FILE_MANAGER
    if FILE_MANAGER == Ptr{Cvoid}(0)
        FILE_MANAGER = default_file_manager()
    end
    FILE_MANAGER
end

end # ObjC

function trash(path::String; force::Bool=false)
    ispath(path) || (force && return) || throw(Base.IOError("trash($(sprint(show, path))) no such file or directory (ENOENT)", -Base.Libc.ENOENT))
    trashfile_ptr = Ref(Ptr{Cvoid}())
    error_ptr = Ref(Ptr{Cvoid}())
    successflag = @ccall objc_msgSend(
        ObjC.filemanager()::Ptr{Cvoid}, ObjC.selector("trashItemAtURL:resultingItemURL:error:")::Ptr{Cvoid},
        ObjC.nsurl(path)::Ptr{Cvoid}, trashfile_ptr::Ptr{Ptr{Cvoid}}, error_ptr::Ptr{Cvoid})::Bool
    if !successflag
        error_ptr[] == Ptr{Cvoid}(0) && error("Failed to trash $path for some unknown reason")
        error_code = @ccall objc_msgSend(error_ptr[]::Ptr{Cvoid}, ObjC.selector("code")::Ptr{Cvoid})::Csize_t
        error_domain = @ccall objc_msgSend(error_ptr[]::Ptr{Cvoid}, ObjC.selector("domain")::Ptr{Cvoid})::Ptr{Cvoid}
        error("Failed to delete $(sprint(show, path)). Darwin error code: $error_code, domain: $(ObjC.ns2string(error_domain))")
    end
    trashfile_nsstring = @ccall objc_msgSend(
        trashfile_ptr[]::Ptr{Cvoid}, ObjC.selector("path")::Ptr{Cvoid})::Ptr{Cvoid}
    trashfile = ObjC.ns2string(trashfile_nsstring)
    TrashFile(trashfile, path, now())
end

function untrash(entry::TrashFile; force::Bool=false, rm::Bool=false)
    if ispath(entry.path)
        if rm
            Base.rm(entry.path, force=true, recursive=true)
        elseif force
            trash(entry.path)
        else
            throw(ArgumentError("$(sprint(show, entry.path)) already exists. `force=true` is required to remove it before restoring the trash entry."))
        end
    end
    # Restore file
    mv(entry.trashfile, entry.path)
    entry.path
end

function untrash(::String)
    error("Restoring files from the trash is not supported on Darwin, and may not be possible (https://developer.apple.com/forums/thread/689800).")
end

function list()
    error("Reading the trash is not supported on Darwin, and may not be possible (https://developer.apple.com/forums/thread/689800).")
end

function empty()
    success(`osascript -e 'tell app "Finder" to empty'`) || error("Failed to empty trash")
    nothing
end

module Trash

using Dates

export trash, untrash, TrashFile

@static if VERSION >= v"1.11"
    eval(Expr(:public, :trashdir, :list, :empty))
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

end

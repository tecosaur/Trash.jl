using Trash
using Documenter
using Org

orgfiles = filter(f -> endswith(f, ".org"),
                  readdir(joinpath(@__DIR__, "src"), join=true))

for orgfile in orgfiles
    mdfile = replace(orgfile, r"\.org$" => ".md")
    read(orgfile, String) |>
        c -> Org.parse(OrgDoc, c) |>
        o -> sprint(markdown, o) |>
        s -> replace(s, r"\.org]" => ".md]") |>
        m -> write(mdfile, m)
end

let indexfile = joinpath(@__DIR__, "src", "index.md")
    index = read(indexfile, String)
    write(indexfile, replace(index, "DS<sub>Store</sub>"=> "DS\\_Store"))
end

makedocs(;
    modules=[Trash],
    format=Documenter.HTML(;
        canonical="https://tecosaur.github.io/Trash.jl",
        assets=["assets/favicon.ico"],
    ),
    pages=[
        "Introduction" => "index.md",
        "Usage" => "usage.md",
    ],
    sitename="Trash.jl",
    warnonly = [:missing_docs, :cross_references],
)

deploydocs(repo="github.com/tecosaur/Trash.jl")

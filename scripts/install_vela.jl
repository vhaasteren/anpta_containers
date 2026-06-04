#!/usr/bin/env julia
# Bootstrap the pinned Vela.jl environment for the anpta container.

using Pkg

function ensure_registries!()
    Pkg.Registry.add("General")
    Pkg.Registry.add(url="https://github.com/abhisrkckl/julia_registry")
end

function main()
    ENV["JULIA_CONDAPKG_BACKEND"] = "Null"
    ensure_registries!()
    Pkg.instantiate()
    Pkg.precompile()
    @eval using Vela
    println("Vela loaded: ", Vela)
end

main()

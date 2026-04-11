"""
    runtests.jl — Test suite entry point.
    Run with: julia --project=. -e 'using Pkg; Pkg.test()'
"""

using Test

include("test_prompt_builder.jl")
include("test_api_client.jl")
include("test_generate.jl")
include("test_assemble_docx.jl")

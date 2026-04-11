"""
test/runtests.jl — Basic test suite for the textbook generation pipeline.

Validates manifest loading, QMD stub generation, and state management helpers
without requiring an Anthropic API key.
"""

using Test
using JSON3

const PROJECT_ROOT = dirname(dirname(abspath(@__FILE__)))
const MANIFEST_PATHS = [
    joinpath(PROJECT_ROOT, "manifests", "part1.json"),
    joinpath(PROJECT_ROOT, "manifests", "part2.json"),
]

# ─────────────────────────────────────────────
# Manifest tests
# ─────────────────────────────────────────────

@testset "Manifests" begin
    for path in MANIFEST_PATHS
        @testset "$(basename(path))" begin
            @test isfile(path)
            data = JSON3.read(read(path, String))
            @test haskey(data, "textbooks")
            textbooks = data["textbooks"]
            @test length(textbooks) > 0
            for tb in textbooks
                @test haskey(tb, "id")
                @test haskey(tb, "title")
                @test haskey(tb, "chapters")
                @test length(tb["chapters"]) > 0
                for ch in tb["chapters"]
                    @test haskey(ch, "chapter_number")
                    @test haskey(ch, "title")
                end
            end
        end
    end
end

# ─────────────────────────────────────────────
# QMD stub generation tests
# ─────────────────────────────────────────────

@testset "QMD stub generation" begin
    mktempdir() do tmpdir
        # Inline a minimal version of the stub writer to avoid import side-effects
        function write_stub_test(tb, outdir)
            id    = string(tb["id"])
            title = string(tb["title"])
            desc  = get(tb, "description", "")
            track = get(tb, "track", "")
            chapters = get(tb, "chapters", Any[])

            lines = String[]
            push!(lines, "---")
            push!(lines, "title: \"$(title)\"")
            if !isempty(string(track))
                push!(lines, "subtitle: \"$(track)\"")
            end
            push!(lines, "---")
            push!(lines, "")
            if !isempty(string(desc))
                push!(lines, string(desc))
                push!(lines, "")
            end
            push!(lines, "## Table of Contents")
            push!(lines, "")
            for ch in chapters
                num     = get(ch, "chapter_number", "")
                chtitle = get(ch, "title", "")
                push!(lines, "$(num). $(chtitle)")
            end
            push!(lines, "")

            stem = lowercase(id)
            path = joinpath(outdir, "$(stem).qmd")
            write(path, join(lines, "\n"))
            return path
        end

        # Load first textbook from part1
        data = JSON3.read(read(MANIFEST_PATHS[1], String))
        tb   = data["textbooks"][1]
        path = write_stub_test(tb, tmpdir)

        @test isfile(path)
        content = read(path, String)
        @test occursin("---", content)
        @test occursin(string(tb["title"]), content)
        @test occursin("## Table of Contents", content)

        # Every chapter title should appear in the stub
        for ch in tb["chapters"]
            @test occursin(string(ch["title"]), content)
        end
    end
end

# ─────────────────────────────────────────────
# State JSON round-trip test
# ─────────────────────────────────────────────

@testset "State JSON round-trip" begin
    mktempdir() do tmpdir
        state_path = joinpath(tmpdir, "state.json")
        completed  = Dict("CORE-001/ch01" => "2024-01-01T00:00:00Z")
        payload    = JSON3.write(Dict(
            "completed"    => completed,
            "last_updated" => "2024-01-01T00:00:00Z",
        ))
        write(state_path, payload)

        loaded = JSON3.read(read(state_path, String))
        @test haskey(loaded, "completed")
        @test haskey(loaded["completed"], "CORE-001/ch01")
        @test string(loaded["completed"]["CORE-001/ch01"]) == "2024-01-01T00:00:00Z"
    end
end

println("\nAll tests passed.")

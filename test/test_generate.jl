"""
    test_generate.jl — Unit tests for src/generate.jl
    Note: ANTHROPIC_API_KEY is not required; no API calls are made.
"""

using Test, JSON3, Dates

# generate.jl includes api_client.jl and prompt_builder.jl via relative path,
# which resolves correctly since include() is relative to the including file.
# The PROGRAM_FILE guard prevents main() from running during tests.
include(joinpath(@__DIR__, "..", "src", "generate.jl"))

@testset "Generate" begin

    @testset "load_state — fresh state when file absent" begin
        mktempdir() do dir
            state_path = joinpath(dir, "state.json")
            @test !isfile(state_path)

            state = load_state(state_path)

            @test state isa GenerationState
            @test state.completed == Dict{String,String}()
            @test state.failed == Dict{String,String}()
            @test !isempty(state.started_at)
            @test !isempty(state.last_updated)
        end
    end

    @testset "save_state → load_state roundtrip" begin
        mktempdir() do dir
            state_path = joinpath(dir, "state.json")

            original = GenerationState(
                Dict("CORE-001/ch01" => "2025-01-01T00:00:00"),
                Dict("CORE-001/ch02" => "network error"),
                "2025-01-01T00:00:00",
                "2025-01-01T00:00:00",
            )

            save_state(original, state_path)
            @test isfile(state_path)

            restored = load_state(state_path)
            @test restored.completed == original.completed
            @test restored.failed == original.failed
            @test restored.started_at == original.started_at
        end
    end

    @testset "save_chapter writes to correct path" begin
        mktempdir() do dir
            key = "CORE-001/ch03"
            content = "# Chapter 3\n\nSome content."

            filepath = save_chapter(key, content, dir)

            @test isfile(filepath)
            @test read(filepath, String) == content

            # Path structure: <output_dir>/<textbook_id>/<chapter>.md
            @test filepath == joinpath(dir, "CORE-001", "ch03.md")
        end
    end

    @testset "parse_args defaults" begin
        args = parse_args(String[])

        @test args[:concurrency] == 5
        @test args[:calibrate] == false
        @test args[:resume] == false
        @test args[:dry_run] == false
        @test isnothing(args[:textbook])
        @test args[:retry_failed] == false
    end

    @testset "parse_args --concurrency" begin
        args = parse_args(["--concurrency", "10"])
        @test args[:concurrency] == 10
    end

    @testset "parse_args --calibrate" begin
        args = parse_args(["--calibrate"])
        @test args[:calibrate] == true
    end

    @testset "parse_args --retry-failed" begin
        args = parse_args(["--retry-failed"])
        @test args[:retry_failed] == true
    end

    @testset "parse_args --textbook" begin
        args = parse_args(["--textbook", "CORE-001"])
        @test args[:textbook] == "CORE-001"
    end

    @testset "parse_args combined flags" begin
        args = parse_args(["--concurrency", "8", "--resume", "--textbook", "SCIML-001"])
        @test args[:concurrency] == 8
        @test args[:resume] == true
        @test args[:textbook] == "SCIML-001"
    end

end

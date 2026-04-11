"""
    test_assemble_docx.jl — Unit tests for src/assemble_docx.jl
    Note: No pandoc invocation; no real chapter files required for metadata tests.
"""

using Test, Dates

# The PROGRAM_FILE guard prevents main() from running during tests.
include(joinpath(@__DIR__, "..", "src", "assemble_docx.jl"))

const PART1 = joinpath(@__DIR__, "..", "manifests", "part1.json")
const PART2 = joinpath(@__DIR__, "..", "manifests", "part2.json")

@testset "AssembleDocx" begin

    @testset "load_textbook_metadata returns all 52 textbooks" begin
        metadata = load_textbook_metadata([PART1, PART2])

        @test metadata isa Dict
        @test length(metadata) == 52

        # Every entry has required fields
        for (id, meta) in metadata
            @test !isempty(id)
            @test !isempty(meta.title)
            @test !isempty(meta.track)
            @test length(meta.chapters) >= 1
            # Each chapter has num and title
            for ch in meta.chapters
                @test ch.num >= 1
                @test !isempty(ch.title)
            end
        end
    end

    @testset "assemble_textbook — produces front matter + TOC + chapters" begin
        mktempdir() do tmpdir
            md_input = joinpath(tmpdir, "markdown")
            md_assembled = joinpath(tmpdir, "assembled")

            # Create a minimal fake textbook with 2 chapters, first present, second absent
            tb_id = "CORE-001"
            tb_dir = joinpath(md_input, tb_id)
            mkpath(tb_dir)
            write(joinpath(tb_dir, "ch01.md"), "# Chapter 1\n\nHello world.")

            meta = (
                title = "Real Analysis for Modelers",
                track = "Core Mathematics — Year 1",
                description = "A rigorous treatment of real analysis.",
                chapters = [(num=1, title="The Real Number System"), (num=2, title="Metric Spaces")],
            )

            result_path = assemble_textbook(tb_id, meta, md_input, md_assembled)

            @test result_path !== nothing
            @test isfile(result_path)

            content = read(result_path, String)

            # Front matter present
            @test occursin("title:", content)
            @test occursin(meta.title, content)
            @test occursin(meta.track, content)

            # Table of Contents present
            @test occursin("Table of Contents", content)
            @test occursin("The Real Number System", content)
            @test occursin("Metric Spaces", content)

            # Actual chapter content included
            @test occursin("Hello world.", content)
        end
    end

    @testset "assemble_textbook — missing chapters produce placeholder text" begin
        mktempdir() do tmpdir
            md_input = joinpath(tmpdir, "markdown")
            md_assembled = joinpath(tmpdir, "assembled")

            tb_id = "CORE-001"
            tb_dir = joinpath(md_input, tb_id)
            mkpath(tb_dir)
            # Write only chapter 1; chapter 2 is intentionally absent
            write(joinpath(tb_dir, "ch01.md"), "# Chapter 1\n\nContent here.")

            meta = (
                title = "Test Book",
                track = "Core",
                description = "Description.",
                chapters = [
                    (num=1, title="Present Chapter"),
                    (num=2, title="Missing Chapter"),
                ],
            )

            result_path = assemble_textbook(tb_id, meta, md_input, md_assembled)
            @test result_path !== nothing

            content = read(result_path, String)

            # Missing chapter placeholder must appear
            @test occursin("[Chapter not yet generated]", content)
            @test occursin("Missing Chapter", content)

            # Present chapter content must also appear
            @test occursin("Content here.", content)
        end
    end

    @testset "assemble_textbook — returns nothing when textbook dir absent" begin
        mktempdir() do tmpdir
            md_input = joinpath(tmpdir, "markdown")
            md_assembled = joinpath(tmpdir, "assembled")
            # No chapter directory created

            meta = (
                title = "Ghost Book",
                track = "Core",
                description = "Desc.",
                chapters = [(num=1, title="Ch1")],
            )

            result = assemble_textbook("GHOST-001", meta, md_input, md_assembled)
            @test result === nothing
        end
    end

end

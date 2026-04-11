"""
    test_prompt_builder.jl — Unit tests for src/prompt_builder.jl
"""

using Test

# Load the PromptBuilder module from src/
include(joinpath(@__DIR__, "..", "src", "prompt_builder.jl"))
using .PromptBuilder

const TEST_MANIFESTS = [
    joinpath(@__DIR__, "..", "manifests", "part1.json"),
    joinpath(@__DIR__, "..", "manifests", "part2.json"),
]

@testset "PromptBuilder" begin

    @testset "load_manifests" begin
        items = load_manifests(TEST_MANIFESTS)

        @test items isa Vector{WorkItem}
        @test length(items) == 438
        @test all(i -> i isa WorkItem, items)

        # Every item has non-empty required fields
        @test all(i -> !isempty(i.textbook_id), items)
        @test all(i -> !isempty(i.chapter_title), items)
        @test all(i -> i.chapter_number >= 1, items)
        @test all(i -> i.total_chapters >= 1, items)
    end

    @testset "work_item_key formatting" begin
        items = load_manifests(TEST_MANIFESTS)

        # First chapter of CORE-001 should have key "CORE-001/ch01"
        core001_ch1 = findfirst(i -> i.textbook_id == "CORE-001" && i.chapter_number == 1, items)
        @test core001_ch1 !== nothing
        key = work_item_key(items[core001_ch1])
        @test key == "CORE-001/ch01"

        # Leading-zero padding: chapter 9 → "ch09", chapter 10 → "ch10"
        item_ch9 = WorkItem("TEST-001", "Title", "Track", 9, "Ch9", "outline", "desc", String[], 10, fill("t", 10))
        @test work_item_key(item_ch9) == "TEST-001/ch09"

        item_ch10 = WorkItem("TEST-001", "Title", "Track", 10, "Ch10", "outline", "desc", String[], 10, fill("t", 10))
        @test work_item_key(item_ch10) == "TEST-001/ch10"
    end

    @testset "build_chapter_prompt" begin
        items = load_manifests(TEST_MANIFESTS)
        item = items[1]
        prompt = build_chapter_prompt(item)

        @test prompt isa String
        @test !isempty(prompt)

        # Must contain chapter number and title
        @test occursin("Chapter $(item.chapter_number)", prompt)
        @test occursin(item.chapter_title, prompt)

        # Must contain Table of Contents section
        @test occursin("Table of Contents", prompt)

        # Must contain the content specification
        @test occursin(item.content_outline, prompt)

        # Must NOT reference Python, R, or MATLAB as the primary language
        prompt_lower = lowercase(prompt)
        @test !occursin("import numpy", prompt_lower)
        @test !occursin("library(ggplot2)", prompt_lower)
        @test !occursin("matlab", prompt_lower)
    end

    @testset "load_system_prompt" begin
        system_prompt_path = joinpath(@__DIR__, "..", "system_prompt.md")
        content = load_system_prompt(system_prompt_path)

        @test content isa String
        @test !isempty(content)

        # Verify it reads the actual file content
        @test content == read(system_prompt_path, String)
    end

end

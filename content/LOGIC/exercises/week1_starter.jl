# Week 1 Starter Exercises — Mathematical Logic (LOGIC)
# Run with: julia --project=. content/LOGIC/exercises/week1_starter.jl

# ── Exercise 1 (Apply) ────────────────────────────────────────────────────
# Implement a truth-table evaluator for propositional formulas.
# A formula is represented as a function Bool... -> Bool.

"""
    truth_table(f, n::Int) -> Matrix{Bool}

Print and return the truth table for an n-variable Boolean function `f`.
Rows enumerate all 2^n combinations of truth values.
"""
function truth_table(f, n::Int)::Matrix{Bool}
    rows = 2^n
    tbl = Matrix{Bool}(undef, rows, n + 1)
    for i in 0:(rows - 1)
        vals = [(i >> (n - k - 1)) & 1 == 1 for k in 0:(n - 1)]
        tbl[i + 1, 1:n] .= vals
        tbl[i + 1, n + 1] = f(vals...)
    end
    return tbl
end

# Example: p ∧ q
f_and(p::Bool, q::Bool) = p && q
println("Truth table for p ∧ q:")
display(truth_table(f_and, 2))

# ── Exercise 2 (Apply) ────────────────────────────────────────────────────
# Cantor pairing function: bijection N×N → N

"""
    cantor_pair(m::Int, n::Int) -> Int

Cantor pairing of non-negative integers `m` and `n`.
"""
function cantor_pair(m::Int, n::Int)::Int
    @assert m >= 0 && n >= 0 "Arguments must be non-negative"
    (m + n) * (m + n + 1) ÷ 2 + m
end

"""
    cantor_unpair(z::Int) -> Tuple{Int,Int}

Inverse of `cantor_pair`: recover (m, n) from the pairing `z`.
"""
function cantor_unpair(z::Int)::Tuple{Int,Int}
    w = floor(Int, (sqrt(8z + 1) - 1) / 2)
    t = (w^2 + w) ÷ 2
    m = z - t
    n = w - m
    return (m, n)
end

println("\nCantor pairing examples:")
for (m, n) in [(0,0), (1,0), (0,1), (2,3)]
    z = cantor_pair(m, n)
    m2, n2 = cantor_unpair(z)
    @assert (m2, n2) == (m, n) "Round-trip failed for ($m, $n)"
    println("  cantor_pair($m, $n) = $z  →  unpair = ($m2, $n2) ✓")
end

# ── Exercise 3 (Analyze) ──────────────────────────────────────────────────
# Show that the set of finite binary strings is countably infinite
# by constructing an explicit enumeration.

"""
    enumerate_binary_strings(n::Int) -> Vector{String}

Return the first `n` binary strings in length-lexicographic order.
"""
function enumerate_binary_strings(n::Int)::Vector{String}
    result = String[]
    k = 0
    len = 0
    while length(result) < n
        for i in 0:(2^len - 1)
            len == 0 && (push!(result, "ε"); break)  # empty string
            push!(result, string(i, base=2, pad=len))
            length(result) >= n && break
        end
        len += 1
    end
    return result[1:min(n, length(result))]
end

println("\nFirst 10 binary strings (length-lex order):")
println(enumerate_binary_strings(10))

println("\nAll Week 1 exercises completed successfully. ✓")

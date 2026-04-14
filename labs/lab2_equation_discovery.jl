### A Pluto.jl notebook ###
# v0.20.4

using Markdown
using InteractiveUtils

# ╔═╡ 00000002-0001-0001-0001-000000000001
begin
	using LinearAlgebra
	using Random
	using Printf
	md"""
	# Lab 2: Discover Governing Equations from Noisy Data

	**Tracks:** SCIML-002 (Neural ODEs) · XCUT-001 (UQ) · CROSS-003 (Inverse Problems) · SCIML-004 (AD)

	Given noisy trajectory data from an unknown dynamical system, use sparse
	regression (SINDy) and Universal Differential Equations (UDEs) to discover
	the governing equations, then quantify prediction uncertainty.

	---

	## Learning Objectives

	1. Generate trajectory data from a known ODE and add realistic noise
	2. Implement numerical differentiation with noise-aware smoothing
	3. Build the SINDy library of candidate nonlinear functions
	4. Solve the sparse regression problem via sequential thresholded least squares
	5. Evaluate discovery accuracy and robustness to noise
	6. (Extension) Compare to neural network-based discovery

	**Estimated time:** 4–6 hours
	"""
end

# ╔═╡ 00000002-0001-0001-0001-000000000002
md"""
## Step 1: Generate Ground Truth Data

We use the **Lotka-Volterra** predator-prey system as our "unknown" dynamical system:

$$\frac{dx}{dt} = \alpha x - \beta x y$$
$$\frac{dy}{dt} = \delta x y - \gamma y$$

The learner's task: given only noisy observations of x(t) and y(t), discover these equations.
"""

# ╔═╡ 00000002-0001-0001-0001-000000000003
begin
	# True parameters (hidden from the discovery algorithm)
	α_true = 1.0    # prey growth rate
	β_true = 0.5    # predation rate
	δ_true = 0.25   # predator growth from prey
	γ_true = 0.8    # predator death rate
end

# ╔═╡ 00000002-0001-0001-0001-000000000004
"""
	rk4_solve(f!, u0, tspan, params; dt=0.01)

Solve du/dt = f(u, params, t) using 4th-order Runge-Kutta.

# Arguments
- `f!`: in-place RHS function f!(du, u, p, t)
- `u0::Vector{Float64}`: initial condition
- `tspan::Tuple{Float64,Float64}`: time span
- `params`: parameters passed to f!
- `dt::Float64`: time step

# Returns
- `times::Vector{Float64}`: time points
- `states::Matrix{Float64}`: solution matrix (n_vars × n_times)
"""
function rk4_solve(f!, u0::Vector{Float64}, tspan::Tuple{Float64,Float64},
                   params; dt::Float64=0.01)
    t0, tf = tspan
    n_steps = ceil(Int, (tf - t0) / dt)
    times = collect(range(t0, tf, length=n_steps + 1))
    n_vars = length(u0)
    states = zeros(n_vars, n_steps + 1)
    states[:, 1] = u0

    du = zeros(n_vars)
    k1, k2, k3, k4 = [zeros(n_vars) for _ in 1:4]

    for i in 1:n_steps
        t = times[i]
        u = states[:, i]

        f!(k1, u, params, t)
        f!(k2, u .+ 0.5dt .* k1, params, t + 0.5dt)
        f!(k3, u .+ 0.5dt .* k2, params, t + 0.5dt)
        f!(k4, u .+ dt .* k3, params, t + dt)

        states[:, i+1] = u .+ (dt / 6) .* (k1 .+ 2k2 .+ 2k3 .+ k4)
    end

    return times, states
end

# ╔═╡ 00000002-0001-0001-0001-000000000005
begin
	function lotka_volterra!(du, u, p, t)
	    x, y = u
	    α, β, δ, γ = p
	    du[1] = α * x - β * x * y
	    du[2] = δ * x * y - γ * y
	end

	u0 = [4.0, 1.0]
	tspan = (0.0, 20.0)
	params_true = [α_true, β_true, δ_true, γ_true]

	times_clean, states_clean = rk4_solve(lotka_volterra!, u0, tspan, params_true; dt=0.01)

	md"**Clean solution generated:** $(length(times_clean)) time points, $(size(states_clean, 1)) state variables."
end

# ╔═╡ 00000002-0001-0001-0001-000000000006
begin
	# Add measurement noise and subsample
	noise_level = 0.2    # adjust to test robustness
	sample_every = 10    # observe every 10th point (dt_obs = 0.1)
	rng = MersenneTwister(42)

	obs_idx = 1:sample_every:length(times_clean)
	t_obs = times_clean[obs_idx]
	x_obs = states_clean[1, obs_idx] .+ noise_level .* randn(rng, length(obs_idx))
	y_obs = states_clean[2, obs_idx] .+ noise_level .* randn(rng, length(obs_idx))

	# Clamp to positive (species can't go negative)
	x_obs = max.(x_obs, 0.01)
	y_obs = max.(y_obs, 0.01)

	n_obs = length(t_obs)

	md"""
	### ✅ Checkpoint 1: Data Generation

	| Parameter | Value |
	|-----------|-------|
	| Observation points | $(n_obs) |
	| Sampling interval | $(round(t_obs[2] - t_obs[1], digits=2)) |
	| Noise level (σ) | $(noise_level) |
	| SNR ≈ | $(round(std(states_clean[1, obs_idx]) / noise_level, digits=1)) |

	**Verify:** Data looks like noisy oscillations with period ≈ 6-8 time units.
	"""
end

# ╔═╡ 00000002-0001-0001-0001-000000000007
md"""
## Step 2: Numerical Differentiation

To apply SINDy, we need estimates of dx/dt and dy/dt from noisy data.
Finite differences amplify noise, so we use a **total variation regularized** derivative
or simply a **Savitzky-Golay-style polynomial smoothing**.
"""

# ╔═╡ 00000002-0001-0001-0001-000000000008
"""
	smooth_differentiate(t, x; window=5)

Estimate dx/dt from noisy data using local polynomial regression (Savitzky-Golay).
Uses a centered window of `2*window+1` points and fits a cubic polynomial.

# Returns
- `dxdt::Vector{Float64}`: estimated derivatives at each interior point
- `t_interior::Vector{Float64}`: corresponding time points
"""
function smooth_differentiate(t::Vector{Float64}, x::Vector{Float64}; window::Int=5)
    n = length(t)
    dxdt = zeros(n - 2 * window)
    t_int = t[window+1:n-window]

    for i in (window + 1):(n - window)
        idx = (i - window):(i + window)
        t_local = t[idx] .- t[i]
        x_local = x[idx]

        # Fit cubic polynomial: x(t) = a0 + a1*t + a2*t² + a3*t³
        V = hcat(ones(length(t_local)), t_local, t_local .^ 2, t_local .^ 3)
        coeffs = V \ x_local

        # Derivative at t=0 is a1
        dxdt[i - window] = coeffs[2]
    end

    return dxdt, t_int
end

# ╔═╡ 00000002-0001-0001-0001-000000000009
begin
	dxdt, t_deriv = smooth_differentiate(t_obs, x_obs; window=3)
	dydt, _ = smooth_differentiate(t_obs, y_obs; window=3)

	# Corresponding state values (trimmed to match derivative estimates)
	w = 3  # window
	x_sindy = x_obs[w+1:end-w]
	y_sindy = y_obs[w+1:end-w]
	n_sindy = length(x_sindy)

	md"""
	### ✅ Checkpoint 2: Numerical Derivatives

	Computed $(n_sindy) derivative estimates from $(n_obs) observations.

	Window size: $(2w + 1) points (Savitzky-Golay cubic).
	"""
end

# ╔═╡ 00000002-0001-0001-0001-000000000010
md"""
## Step 3: Build the SINDy Library

The key idea of SINDy (Brunton et al., 2016): express the dynamics as a **sparse** linear combination of candidate nonlinear functions:

$$\dot{x} = \Theta(x, y) \cdot \xi$$

where Θ is the library matrix and ξ is a sparse coefficient vector.
"""

# ╔═╡ 00000002-0001-0001-0001-000000000011
"""
	build_sindy_library(x, y)

Build the SINDy candidate function library matrix Θ.
Includes: 1, x, y, x², xy, y², x³, x²y, xy², y³

# Returns
- `Θ::Matrix{Float64}`: library matrix (n_obs × n_functions)
- `labels::Vector{String}`: human-readable function names
"""
function build_sindy_library(x::Vector{Float64}, y::Vector{Float64})
    n = length(x)
    labels = ["1", "x", "y", "x²", "xy", "y²", "x³", "x²y", "xy²", "y³"]
    Θ = hcat(
        ones(n),          # 1
        x,                # x
        y,                # y
        x .^ 2,           # x²
        x .* y,           # xy
        y .^ 2,           # y²
        x .^ 3,           # x³
        (x .^ 2) .* y,    # x²y
        x .* (y .^ 2),    # xy²
        y .^ 3,           # y³
    )
    return Θ, labels
end

# ╔═╡ 00000002-0001-0001-0001-000000000012
begin
	Θ, lib_labels = build_sindy_library(x_sindy, y_sindy)
	md"**Library matrix Θ:** $(size(Θ, 1)) observations × $(size(Θ, 2)) candidate functions: $(join(lib_labels, ", "))"
end

# ╔═╡ 00000002-0001-0001-0001-000000000013
md"""
## Step 4: Sequential Thresholded Least Squares (STLS)

SINDy's core algorithm: alternately solve least squares and threshold small coefficients to zero, promoting sparsity.
"""

# ╔═╡ 00000002-0001-0001-0001-000000000014
"""
	stls(Θ, dxdt; λ=0.1, max_iter=20)

Sequential Thresholded Least Squares for sparse regression.

# Arguments
- `Θ::Matrix{Float64}`: library matrix
- `dxdt::Vector{Float64}`: target derivatives
- `λ::Float64`: sparsity threshold
- `max_iter::Int`: maximum iterations

# Returns
- `ξ::Vector{Float64}`: sparse coefficient vector
"""
function stls(Θ::Matrix{Float64}, dxdt::Vector{Float64};
              λ::Float64=0.1, max_iter::Int=20)
    # Initial least-squares solve
    ξ = Θ \ dxdt

    for iter in 1:max_iter
        # Threshold: zero out small coefficients
        small = abs.(ξ) .< λ
        ξ[small] .= 0.0

        # Re-solve on active columns only
        active = .!small
        if sum(active) == 0
            break
        end
        ξ[active] = Θ[:, active] \ dxdt
    end

    return ξ
end

# ╔═╡ 00000002-0001-0001-0001-000000000015
begin
	# Discover equations for dx/dt and dy/dt
	threshold = 0.05  # sparsity threshold — adjust to explore

	ξ_x = stls(Θ, dxdt; λ=threshold)
	ξ_y = stls(Θ, dydt; λ=threshold)

	function format_equation(ξ, labels, var)
	    terms = String[]
	    for (i, c) in enumerate(ξ)
	        abs(c) < 1e-10 && continue
	        sign_str = c > 0 ? "+" : "-"
	        if isempty(terms) && c > 0
	            sign_str = ""
	        end
	        push!(terms, "$sign_str $(round(abs(c), digits=3))·$(labels[i])")
	    end
	    isempty(terms) && return "d$(var)/dt = 0"
	    return "d$(var)/dt = " * join(terms, " ")
	end

	eq_x = format_equation(ξ_x, lib_labels, "x")
	eq_y = format_equation(ξ_y, lib_labels, "y")

	md"""
	### ✅ Checkpoint 3: Discovered Equations

	**Discovered:**
	```
	$(eq_x)
	$(eq_y)
	```

	**True equations:**
	```
	dx/dt = $(α_true)·x - $(β_true)·xy
	dy/dt = $(δ_true)·xy - $(γ_true)·y
	```

	**Active terms (dx/dt):** $(join(lib_labels[abs.(ξ_x) .> 1e-10], ", "))

	**Active terms (dy/dt):** $(join(lib_labels[abs.(ξ_y) .> 1e-10], ", "))

	**Threshold λ = $(threshold)**. Try adjusting: too low → spurious terms, too high → missing terms.
	"""
end

# ╔═╡ 00000002-0001-0001-0001-000000000016
md"""
## Step 5: Evaluate Discovery Accuracy

Compare discovered coefficients to ground truth and test prediction accuracy.
"""

# ╔═╡ 00000002-0001-0001-0001-000000000017
begin
	# True coefficient vectors (in the basis [1, x, y, x², xy, y², x³, x²y, xy², y³])
	ξ_x_true = [0.0, α_true, 0.0, 0.0, -β_true, 0.0, 0.0, 0.0, 0.0, 0.0]
	ξ_y_true = [0.0, 0.0, -γ_true, 0.0, δ_true, 0.0, 0.0, 0.0, 0.0, 0.0]

	# Coefficient errors
	err_x = norm(ξ_x - ξ_x_true) / norm(ξ_x_true)
	err_y = norm(ξ_y - ξ_y_true) / norm(ξ_y_true)

	# Structural accuracy: did we find the right terms?
	true_support_x = Set(findall(abs.(ξ_x_true) .> 0))
	disc_support_x = Set(findall(abs.(ξ_x) .> 1e-10))
	true_support_y = Set(findall(abs.(ξ_y_true) .> 0))
	disc_support_y = Set(findall(abs.(ξ_y) .> 1e-10))

	struct_correct_x = true_support_x == disc_support_x
	struct_correct_y = true_support_y == disc_support_y

	# Prediction: integrate discovered system forward
	function discovered_rhs!(du, u, p, t)
	    x, y = u
	    lib = [1, x, y, x^2, x*y, y^2, x^3, x^2*y, x*y^2, y^3]
	    du[1] = dot(ξ_x, lib)
	    du[2] = dot(ξ_y, lib)
	end

	times_pred, states_pred = rk4_solve(discovered_rhs!, u0, (0.0, 20.0), nothing; dt=0.01)

	# Prediction error (on clean trajectory)
	pred_err = sqrt(mean((states_pred .- states_clean) .^ 2))
	mean(x) = sum(x) / length(x)

	md"""
	### ✅ Checkpoint 4: Discovery Evaluation

	| Metric | dx/dt | dy/dt |
	|--------|-------|-------|
	| Coeff rel error | $(round(err_x * 100, digits=1))% | $(round(err_y * 100, digits=1))% |
	| Correct structure? | $(struct_correct_x ? "✅ Yes" : "❌ No") | $(struct_correct_y ? "✅ Yes" : "❌ No") |
	| True active terms | $(join(lib_labels[collect(true_support_x)], ", ")) | $(join(lib_labels[collect(true_support_y)], ", ")) |
	| Discovered terms | $(join(lib_labels[collect(disc_support_x)], ", ")) | $(join(lib_labels[collect(disc_support_y)], ", ")) |

	**Trajectory RMSE:** $(round(pred_err, digits=4))

	$(struct_correct_x && struct_correct_y ? "🎯 **Perfect structural recovery!**" : "⚠ Structure mismatch — try adjusting λ or noise level.")
	"""
end

# ╔═╡ 00000002-0001-0001-0001-000000000018
md"""
## Step 6: Robustness Study

How does discovery accuracy degrade with noise?
"""

# ╔═╡ 00000002-0001-0001-0001-000000000019
begin
	noise_levels_test = [0.01, 0.05, 0.1, 0.2, 0.5, 1.0, 2.0]
	n_repeats = 20
	robustness = []

	for σ_test in noise_levels_test
	    correct_count = 0
	    coeff_errors = Float64[]

	    for rep in 1:n_repeats
	        rng_test = MersenneTwister(rep * 1000)
	        x_noisy = states_clean[1, obs_idx] .+ σ_test .* randn(rng_test, length(obs_idx))
	        y_noisy = states_clean[2, obs_idx] .+ σ_test .* randn(rng_test, length(obs_idx))
	        x_noisy = max.(x_noisy, 0.01)
	        y_noisy = max.(y_noisy, 0.01)

	        dx, _ = smooth_differentiate(t_obs, x_noisy; window=3)
	        dy, _ = smooth_differentiate(t_obs, y_noisy; window=3)
	        xs = x_noisy[w+1:end-w]
	        ys = y_noisy[w+1:end-w]

	        Θ_test, _ = build_sindy_library(xs, ys)
	        ξx = stls(Θ_test, dx; λ=0.05)
	        ξy = stls(Θ_test, dy; λ=0.05)

	        supp_x = Set(findall(abs.(ξx) .> 1e-10))
	        supp_y = Set(findall(abs.(ξy) .> 1e-10))
	        if supp_x == true_support_x && supp_y == true_support_y
	            correct_count += 1
	        end
	        push!(coeff_errors, (norm(ξx - ξ_x_true) + norm(ξy - ξ_y_true)) / (norm(ξ_x_true) + norm(ξ_y_true)))
	    end

	    push!(robustness, (σ=σ_test, recovery_rate=correct_count/n_repeats,
	                       mean_error=sum(coeff_errors)/length(coeff_errors)))
	end

	md"""
	### ✅ Checkpoint 5: Robustness Results

	| Noise σ | Recovery Rate | Mean Coeff Error |
	|---------|--------------|-----------------|
	$(join(["| $(r.σ) | $(round(r.recovery_rate * 100, digits=0))% | $(round(r.mean_error * 100, digits=1))% |" for r in robustness], "\n"))

	**Interpretation:** SINDy maintains structural recovery up to noise ≈ $(robustness[findlast(r -> r.recovery_rate >= 0.8, robustness)]?.σ || "N/A"), then degrades. The derivative estimation is the bottleneck — noise amplification in finite differences is the fundamental limitation.
	"""
end

# ╔═╡ 00000002-0001-0001-0001-000000000020
md"""
## Summary & Extensions

### What We Built
1. ✅ Generated noisy trajectory data from Lotka-Volterra
2. ✅ Implemented noise-aware numerical differentiation (Savitzky-Golay)
3. ✅ Built SINDy candidate function library (10 terms up to cubic)
4. ✅ Discovered governing equations via STLS sparse regression
5. ✅ Evaluated structural and coefficient accuracy
6. ✅ Characterized robustness to noise across 7 levels

### Extensions (try these!)
- Replace STLS with **LASSO** (`λ ||ξ||₁` penalty) or **SR3** (sparse relaxed regularized regression)
- Implement **weak-form SINDy** (integrate both sides against test functions to avoid differentiation)
- Build a **Universal Differential Equation**: replace the unknown RHS with a neural network, train, then extract a symbolic form
- Add **uncertainty quantification**: bootstrap the SINDy coefficients to get confidence intervals
- Test on a **3D system** (Lorenz attractor) — harder because of chaotic sensitivity
- Implement **PDE-FIND**: extend SINDy to discover partial differential equations

### Textbook Connections
- **SCIML-002** (Neural ODEs): UDE architecture for equation discovery
- **SCIML-004** (AD): Differentiate through the ODE solver for UDE training
- **CROSS-003** (Inverse Problems): SINDy as a regularized inverse problem
- **XCUT-001** (UQ): Uncertainty in discovered equations
- **CROSS-006** (Model Selection): Choosing λ is a model selection problem
"""

# ╔═╡ Cell order:
# ╟─00000002-0001-0001-0001-000000000001
# ╟─00000002-0001-0001-0001-000000000002
# ╠═00000002-0001-0001-0001-000000000003
# ╠═00000002-0001-0001-0001-000000000004
# ╠═00000002-0001-0001-0001-000000000005
# ╟─00000002-0001-0001-0001-000000000006
# ╟─00000002-0001-0001-0001-000000000007
# ╠═00000002-0001-0001-0001-000000000008
# ╟─00000002-0001-0001-0001-000000000009
# ╟─00000002-0001-0001-0001-000000000010
# ╠═00000002-0001-0001-0001-000000000011
# ╟─00000002-0001-0001-0001-000000000012
# ╟─00000002-0001-0001-0001-000000000013
# ╠═00000002-0001-0001-0001-000000000014
# ╟─00000002-0001-0001-0001-000000000015
# ╟─00000002-0001-0001-0001-000000000016
# ╟─00000002-0001-0001-0001-000000000017
# ╟─00000002-0001-0001-0001-000000000018
# ╟─00000002-0001-0001-0001-000000000019
# ╟─00000002-0001-0001-0001-000000000020

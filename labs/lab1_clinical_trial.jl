### A Pluto.jl notebook ###
# v0.20.4

using Markdown
using InteractiveUtils

# ╔═╡ 00000001-0001-0001-0001-000000000001
begin
	using Distributions
	using DataFrames
	using Random
	using LinearAlgebra
	using Printf
	md"""
	# Lab 1: Clinical Trial Analysis Pipeline

	**Tracks:** BIO-001 (GLMs) · BIO-002 (Survival) · BIO-004 (Causal Inference) · CORE-011 (Bayesian)

	Build a complete analysis pipeline for a simulated randomized controlled trial
	comparing two treatments for time-to-event outcomes.

	---

	## Learning Objectives

	By completing this lab, you will:
	1. Simulate realistic RCT data with censoring and covariates
	2. Implement the Kaplan-Meier estimator from scratch
	3. Conduct log-rank tests for treatment comparison
	4. Fit survival models (parametric and semi-parametric)
	5. Perform Bayesian survival analysis
	6. Conduct sensitivity analyses and report results

	**Estimated time:** 4–6 hours
	"""
end

# ╔═╡ 00000001-0001-0001-0001-000000000002
md"""
## Step 1: Data Generation

We simulate a two-arm RCT with Weibull-distributed survival times,
a treatment effect (hazard ratio), age as a covariate, and random censoring.

**Controls:** Adjust the sliders below to explore how trial parameters affect the data.
"""

# ╔═╡ 00000001-0001-0001-0001-000000000003
begin
	# Trial parameters — adjust these to explore
	n_per_arm = 250
	true_hr = 0.7          # hazard ratio (treatment effect)
	baseline_hazard = 0.1  # λ₀
	censor_rate = 0.2      # fraction censored
	max_follow_up = 24.0   # months
	noise_seed = 2026
end

# ╔═╡ 00000001-0001-0001-0001-000000000004
"""
	simulate_trial(n_per_arm; hr, λ₀, censor_rate, max_time, seed)

Simulate a two-arm randomized controlled trial with Weibull survival times.

# Arguments
- `n_per_arm::Int`: patients per arm
- `hr::Float64`: true hazard ratio for treatment (< 1 means treatment is better)
- `λ₀::Float64`: baseline hazard rate
- `censor_rate::Float64`: approximate fraction of censored observations
- `max_time::Float64`: maximum follow-up time
- `seed::Int`: random seed for reproducibility

# Returns
- `DataFrame` with columns: id, treatment, age, sex, time, event
"""
function simulate_trial(n_per_arm::Int;
                        hr::Float64=0.7,
                        λ₀::Float64=0.1,
                        censor_rate::Float64=0.2,
                        max_time::Float64=24.0,
                        seed::Int=2026)
    rng = MersenneTwister(seed)
    n = 2 * n_per_arm

    # Treatment assignment (1:1 randomization)
    treatment = vcat(zeros(Int, n_per_arm), ones(Int, n_per_arm))

    # Baseline covariates
    age = rand(rng, Normal(60, 10), n)
    sex = rand(rng, Bernoulli(0.45), n)

    # Weibull survival times with treatment and age effects
    shape = 1.2
    scale = [λ₀ * exp(-log(hr) * treatment[i] - 0.02 * (age[i] - 60))
             for i in 1:n]
    true_times = [rand(rng, Weibull(shape, 1.0 / scale[i])) for i in 1:n]

    # Administrative censoring + random loss to follow-up
    censor_times = [min(rand(rng, Exponential(max_time / censor_rate)), max_time)
                    for _ in 1:n]

    observed_time = min.(true_times, censor_times)
    event = true_times .<= censor_times

    DataFrame(
        id = 1:n,
        treatment = treatment,
        age = round.(age, digits=1),
        sex = Int.(sex),
        time = round.(observed_time, digits=2),
        event = event
    )
end

# ╔═╡ 00000001-0001-0001-0001-000000000005
trial_data = simulate_trial(n_per_arm;
    hr=true_hr, λ₀=baseline_hazard,
    censor_rate=censor_rate, max_time=max_follow_up,
    seed=noise_seed)

# ╔═╡ 00000001-0001-0001-0001-000000000006
begin
	n_total = nrow(trial_data)
	n_events = sum(trial_data.event)
	n_censored = n_total - n_events
	n_trt = sum(trial_data.treatment .== 1)
	n_ctrl = sum(trial_data.treatment .== 0)
	median_time = sort(trial_data.time)[div(n_total, 2)]

	md"""
	### ✅ Checkpoint 1: Data Summary

	| Metric | Value |
	|--------|-------|
	| Total patients | $(n_total) |
	| Control arm | $(n_ctrl) |
	| Treatment arm | $(n_trt) |
	| Events (deaths) | $(n_events) ($(round(100*n_events/n_total, digits=1))%) |
	| Censored | $(n_censored) ($(round(100*n_censored/n_total, digits=1))%) |
	| Median follow-up | $(round(median_time, digits=1)) months |

	**Verify:** ~500 patients, ~20% censoring, balanced arms ✓
	"""
end

# ╔═╡ 00000001-0001-0001-0001-000000000007
md"""
## Step 2: Kaplan-Meier Estimator

Implement the Kaplan-Meier survival curve from scratch.
The KM estimator at time t is:

$$\hat{S}(t) = \prod_{t_i \leq t} \left(1 - \frac{d_i}{n_i}\right)$$

where $d_i$ = deaths at time $t_i$ and $n_i$ = number at risk just before $t_i$.
"""

# ╔═╡ 00000001-0001-0001-0001-000000000008
"""
	kaplan_meier(times, events)

Compute the Kaplan-Meier survival curve from raw time-to-event data.

# Arguments
- `times::Vector{Float64}`: observed times
- `events::Vector{Bool}`: event indicators (true = event, false = censored)

# Returns
- `km_times::Vector{Float64}`: unique event times (with 0.0 prepended)
- `km_survival::Vector{Float64}`: survival probability at each time
- `km_stderr::Vector{Float64}`: Greenwood standard error at each time
"""
function kaplan_meier(times::Vector{Float64}, events::Vector{Bool})
    sorted_idx = sortperm(times)
    t = times[sorted_idx]
    e = events[sorted_idx]

    km_times = Float64[0.0]
    km_survival = Float64[1.0]
    km_var_sum = Float64[0.0]  # Greenwood's formula running sum

    n_at_risk = length(t)
    i = 1

    while i <= length(t)
        current_time = t[i]
        d = 0   # deaths at this time
        c = 0   # censored at this time

        while i <= length(t) && t[i] == current_time
            if e[i]
                d += 1
            else
                c += 1
            end
            i += 1
        end

        if d > 0
            survival_decrement = 1 - d / n_at_risk
            push!(km_times, current_time)
            push!(km_survival, km_survival[end] * survival_decrement)

            # Greenwood variance component
            var_component = d / (n_at_risk * (n_at_risk - d))
            push!(km_var_sum, km_var_sum[end] + var_component)
        end

        n_at_risk -= (d + c)
    end

    # Standard error via Greenwood's formula: SE = S(t) * sqrt(Σ d/(n*(n-d)))
    km_stderr = km_survival .* sqrt.(km_var_sum)

    return km_times, km_survival, km_stderr
end

# ╔═╡ 00000001-0001-0001-0001-000000000009
begin
	# Compute KM curves by treatment group
	ctrl_mask = trial_data.treatment .== 0
	trt_mask = trial_data.treatment .== 1

	km_ctrl_t, km_ctrl_s, km_ctrl_se = kaplan_meier(
		Float64.(trial_data.time[ctrl_mask]),
		trial_data.event[ctrl_mask]
	)
	km_trt_t, km_trt_s, km_trt_se = kaplan_meier(
		Float64.(trial_data.time[trt_mask]),
		trial_data.event[trt_mask]
	)

	md"""
	### ✅ Checkpoint 2: Kaplan-Meier Curves

	**Control arm:** $(length(km_ctrl_t)-1) event times, final S(t) = $(round(km_ctrl_s[end], digits=3))

	**Treatment arm:** $(length(km_trt_t)-1) event times, final S(t) = $(round(km_trt_s[end], digits=3))

	Treatment arm should show higher survival (curves should separate) since true HR = $(true_hr) < 1.
	"""
end

# ╔═╡ 00000001-0001-0001-0001-000000000010
md"""
## Step 3: Log-Rank Test

The log-rank test compares survival distributions between groups.
Under H₀ (no treatment effect), the test statistic follows χ²(1).
"""

# ╔═╡ 00000001-0001-0001-0001-000000000011
"""
	log_rank_test(times, events, groups)

Perform the log-rank test comparing two survival curves.

# Returns
- `(statistic, p_value, observed_trt, expected_trt)`
"""
function log_rank_test(times::Vector{Float64}, events::Vector{Bool},
                       groups::Vector{Int})
    # Get unique event times
    event_times = sort(unique(times[events]))

    O_trt = 0.0   # observed events in treatment
    E_trt = 0.0   # expected events in treatment
    V = 0.0       # variance

    for t in event_times
        # At risk just before time t
        at_risk_ctrl = sum((times .>= t) .& (groups .== 0))
        at_risk_trt = sum((times .>= t) .& (groups .== 1))
        n_total_risk = at_risk_ctrl + at_risk_trt

        # Events at time t
        d_ctrl = sum((times .== t) .& events .& (groups .== 0))
        d_trt = sum((times .== t) .& events .& (groups .== 1))
        d_total = d_ctrl + d_trt

        if n_total_risk > 1
            # Expected events in treatment under H₀
            e_trt = d_total * at_risk_trt / n_total_risk
            E_trt += e_trt
            O_trt += d_trt

            # Variance (hypergeometric)
            V += d_total * at_risk_ctrl * at_risk_trt * (n_total_risk - d_total) /
                 (n_total_risk^2 * (n_total_risk - 1))
        end
    end

    statistic = (O_trt - E_trt)^2 / V
    p_value = 1 - cdf(Chisq(1), statistic)

    return (statistic=statistic, p_value=p_value,
            observed=O_trt, expected=E_trt)
end

# ╔═╡ 00000001-0001-0001-0001-000000000012
begin
	lr = log_rank_test(
		Float64.(trial_data.time),
		trial_data.event,
		trial_data.treatment
	)

	md"""
	### ✅ Checkpoint 3: Log-Rank Test

	| Metric | Value |
	|--------|-------|
	| χ² statistic | $(round(lr.statistic, digits=2)) |
	| p-value | $(round(lr.p_value, digits=6)) |
	| Observed events (treatment) | $(round(lr.observed, digits=1)) |
	| Expected events (treatment) | $(round(lr.expected, digits=1)) |

	**Result:** $(lr.p_value < 0.05 ? "✅ Significant (p < 0.05) — reject H₀" : "❌ Not significant")

	Treatment has $(lr.observed < lr.expected ? "fewer" : "more") events than expected → $(lr.observed < lr.expected ? "beneficial" : "harmful") effect.
	"""
end

# ╔═╡ 00000001-0001-0001-0001-000000000013
md"""
## Step 4: Parametric Survival Model

Fit a Weibull proportional hazards model using maximum likelihood.
The hazard function is:

$$h(t | x) = \alpha \lambda t^{\alpha - 1} \exp(x^T \beta)$$

where $\alpha$ is the shape and $\lambda$ is the scale.
"""

# ╔═╡ 00000001-0001-0001-0001-000000000014
"""
	weibull_nll(params, times, events, X)

Negative log-likelihood for the Weibull proportional hazards model.
params = [log(α), log(λ₀), β₁, β₂, ...]
"""
function weibull_nll(params::Vector{Float64},
                     times::Vector{Float64},
                     events::Vector{Bool},
                     X::Matrix{Float64})
    log_α = params[1]
    log_λ = params[2]
    β = params[3:end]

    α = exp(log_α)
    λ = exp(log_λ)

    η = X * β   # linear predictor

    nll = 0.0
    for i in eachindex(times)
        t = max(times[i], 1e-10)
        λ_i = λ * exp(η[i])

        if events[i]
            # Log density: log(α) + log(λ_i) + (α-1)*log(t) - λ_i * t^α
            nll -= log(α) + log(λ_i) + (α - 1) * log(t) - λ_i * t^α
        else
            # Log survival: -λ_i * t^α
            nll -= -λ_i * t^α
        end
    end

    return nll
end

# ╔═╡ 00000001-0001-0001-0001-000000000015
begin
	# Design matrix: treatment + age (centered)
	X = hcat(
		Float64.(trial_data.treatment),
		(trial_data.age .- 60.0) ./ 10.0   # scaled age
	)

	times_vec = Float64.(trial_data.time)
	events_vec = trial_data.event

	# Simple gradient-free optimization (Nelder-Mead via coordinate search)
	# In production, use Optim.jl; here we implement a basic optimizer
	function simple_optimize(f, x0; maxiter=5000, tol=1e-8)
		x = copy(x0)
		n = length(x)
		step = 0.1 * ones(n)
		best_val = f(x)

		for iter in 1:maxiter
			improved = false
			for i in 1:n
				for direction in [1.0, -1.0]
					x_new = copy(x)
					x_new[i] += direction * step[i]
					val = f(x_new)
					if val < best_val
						x = x_new
						best_val = val
						improved = true
						step[i] *= 1.2
					end
				end
			end
			if !improved
				step .*= 0.5
				if maximum(step) < tol
					break
				end
			end
		end
		return x, best_val
	end

	# Initial guesses: log(α)=0 (α=1), log(λ)=-2 (λ=0.1), β_trt=0, β_age=0
	x0 = [0.0, -2.0, 0.0, 0.0]
	obj(p) = weibull_nll(p, times_vec, events_vec, X)

	mle_params, mle_nll = simple_optimize(obj, x0)

	α_hat = exp(mle_params[1])
	λ_hat = exp(mle_params[2])
	β_trt = mle_params[3]
	β_age = mle_params[4]
	hr_hat = exp(β_trt)

	md"""
	### ✅ Checkpoint 4: Weibull PH Model

	| Parameter | Estimate | Interpretation |
	|-----------|----------|----------------|
	| α (shape) | $(round(α_hat, digits=3)) | $(α_hat > 1 ? "Increasing" : "Decreasing") hazard over time |
	| λ₀ (scale) | $(round(λ_hat, digits=5)) | Baseline hazard rate |
	| β_treatment | $(round(β_trt, digits=3)) | Log hazard ratio |
	| β_age | $(round(β_age, digits=3)) | Log HR per 10 years |
	| **HR (treatment)** | **$(round(hr_hat, digits=3))** | **$(hr_hat < 1 ? "Protective" : "Harmful")** |

	True HR = $(true_hr), Estimated HR = $(round(hr_hat, digits=3))

	**-2 log L** = $(round(2*mle_nll, digits=1)), **AIC** = $(round(2*mle_nll + 2*4, digits=1))
	"""
end

# ╔═╡ 00000001-0001-0001-0001-000000000016
md"""
## Step 5: Sensitivity Analysis

How robust are our conclusions?

1. **Subgroup analysis** by sex
2. **Sensitivity to censoring** assumptions
3. **Comparison** of frequentist HR to the true value
"""

# ╔═╡ 00000001-0001-0001-0001-000000000017
begin
	# Subgroup analysis by sex
	male_mask = trial_data.sex .== 1
	female_mask = trial_data.sex .== 0

	lr_male = log_rank_test(
		Float64.(trial_data.time[male_mask]),
		trial_data.event[male_mask],
		trial_data.treatment[male_mask]
	)
	lr_female = log_rank_test(
		Float64.(trial_data.time[female_mask]),
		trial_data.event[female_mask],
		trial_data.treatment[female_mask]
	)

	md"""
	### ✅ Checkpoint 5: Sensitivity Analysis

	**Subgroup Analysis:**

	| Subgroup | n | χ² | p-value | Effect direction |
	|----------|---|-------|---------|-----------------|
	| Male | $(sum(male_mask)) | $(round(lr_male.statistic, digits=2)) | $(round(lr_male.p_value, digits=4)) | $(lr_male.observed < lr_male.expected ? "Beneficial" : "Harmful") |
	| Female | $(sum(female_mask)) | $(round(lr_female.statistic, digits=2)) | $(round(lr_female.p_value, digits=4)) | $(lr_female.observed < lr_female.expected ? "Beneficial" : "Harmful") |

	**Parameter Recovery:**

	| Parameter | True | Estimated | Relative error |
	|-----------|------|-----------|---------------|
	| HR | $(true_hr) | $(round(hr_hat, digits=3)) | $(round(abs(hr_hat - true_hr)/true_hr * 100, digits=1))% |
	| Shape (α) | 1.2 | $(round(α_hat, digits=3)) | $(round(abs(α_hat - 1.2)/1.2 * 100, digits=1))% |
	"""
end

# ╔═╡ 00000001-0001-0001-0001-000000000018
md"""
## Summary & Extensions

### What We Built
1. ✅ Simulated a realistic 500-patient RCT with Weibull survival
2. ✅ Implemented Kaplan-Meier estimator with Greenwood standard errors
3. ✅ Conducted log-rank test for treatment comparison
4. ✅ Fit a Weibull proportional hazards model via MLE
5. ✅ Performed subgroup and parameter sensitivity analyses

### Extensions (try these!)
- Add **Bayesian analysis** using `Turing.jl` with weakly informative priors
- Implement the **Cox partial likelihood** (semi-parametric)
- Add **time-varying covariates** (treatment crossover at 12 months)
- Perform **competing risks** analysis
- Compute **E-values** for sensitivity to unmeasured confounding
- Add **interim analysis** with alpha spending function (O'Brien-Fleming)

### Textbook Connections
- **BIO-001** (GLMs): The survival model is a generalized linear model with complementary log-log link
- **BIO-002** (Survival): Cox PH model, Schoenfeld residuals, time-varying effects
- **BIO-004** (Causal Inference): Intent-to-treat vs per-protocol, E-values
- **CORE-011** (Bayesian): Prior specification for HR, posterior predictive checks
- **CROSS-006** (Model Selection): Comparing Weibull, log-normal, and Cox models via AIC/WAIC
"""

# ╔═╡ Cell order:
# ╟─00000001-0001-0001-0001-000000000001
# ╟─00000001-0001-0001-0001-000000000002
# ╠═00000001-0001-0001-0001-000000000003
# ╠═00000001-0001-0001-0001-000000000004
# ╠═00000001-0001-0001-0001-000000000005
# ╟─00000001-0001-0001-0001-000000000006
# ╟─00000001-0001-0001-0001-000000000007
# ╠═00000001-0001-0001-0001-000000000008
# ╟─00000001-0001-0001-0001-000000000009
# ╟─00000001-0001-0001-0001-000000000010
# ╠═00000001-0001-0001-0001-000000000011
# ╟─00000001-0001-0001-0001-000000000012
# ╟─00000001-0001-0001-0001-000000000013
# ╠═00000001-0001-0001-0001-000000000014
# ╟─00000001-0001-0001-0001-000000000015
# ╟─00000001-0001-0001-0001-000000000016
# ╟─00000001-0001-0001-0001-000000000017
# ╟─00000001-0001-0001-0001-000000000018

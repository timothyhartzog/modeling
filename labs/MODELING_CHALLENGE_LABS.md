# Modeling Challenge Labs

## Overview

Five integrative capstone labs that span multiple textbooks in the curriculum.
Each lab is a self-contained research project with scaffolded steps, checkpoints,
and extension challenges. Designed as Pluto.jl notebooks or standalone Julia scripts.

---

# Lab 1: Clinical Trial Analysis Pipeline
**Tracks:** BIOS-001 (GLMs), BIOS-002 (Survival), BIOS-004 (Causal Inference), CORE-008 (Bayesian)

## Objective
Build a complete analysis pipeline for a simulated randomized controlled trial comparing
two treatments for time-to-event outcomes, including frequentist and Bayesian approaches,
sensitivity analyses, and causal interpretation.

## Scaffolded Steps

### Step 1: Data Generation (Checkpoint 1)
```julia
using Distributions, DataFrames, Random
Random.seed!(2026)

function simulate_trial(n_per_arm::Int; hr::Float64=0.7, λ₀::Float64=0.1,
                         censor_rate::Float64=0.2, max_time::Float64=24.0)
    n = 2 * n_per_arm
    treatment = vcat(zeros(Int, n_per_arm), ones(Int, n_per_arm))
    
    # Covariates
    age = rand(Normal(60, 10), n)
    sex = rand(Bernoulli(0.45), n)
    
    # True survival times (Weibull with treatment effect)
    shape = 1.2
    scale = λ₀ .* exp.(-log(hr) .* treatment .- 0.02 .* (age .- 60))
    true_times = rand.(Weibull.(shape, 1.0 ./ scale))
    
    # Censoring
    censor_times = rand(Exponential(max_time / censor_rate), n)
    censor_times = min.(censor_times, max_time)
    
    observed_time = min.(true_times, censor_times)
    event = true_times .<= censor_times
    
    DataFrame(
        id = 1:n,
        treatment = treatment,
        age = round.(age, digits=1),
        sex = sex,
        time = round.(observed_time, digits=2),
        event = event
    )
end

trial_data = simulate_trial(250; hr=0.7)
```

**Checkpoint 1:** Verify trial has ~500 patients, ~20% censoring, balanced arms.

### Step 2: Kaplan-Meier Estimation (Checkpoint 2)
```julia
# Implement Kaplan-Meier estimator from scratch
function kaplan_meier(times::Vector{Float64}, events::Vector{Bool})
    sorted_idx = sortperm(times)
    t = times[sorted_idx]
    e = events[sorted_idx]
    
    unique_times = Float64[0.0]
    survival = Float64[1.0]
    n_at_risk = length(t)
    
    i = 1
    while i <= length(t)
        # Count events and censored at this time
        current_time = t[i]
        d = 0  # deaths
        c = 0  # censored
        while i <= length(t) && t[i] == current_time
            d += e[i]
            c += !e[i]
            i += 1
        end
        
        if d > 0
            push!(unique_times, current_time)
            push!(survival, survival[end] * (1 - d / n_at_risk))
        end
        n_at_risk -= (d + c)
    end
    
    return unique_times, survival
end

# Plot KM curves by treatment group
# [FIGURE: Kaplan-Meier survival curves with 95% CI bands, stratified by treatment]
```

**Checkpoint 2:** KM curves show treatment separation. Log-rank test p < 0.05.

### Step 3: Cox Proportional Hazards Model (Checkpoint 3)
```julia
# Fit Cox PH model using partial likelihood
# Check proportional hazards assumption via Schoenfeld residuals
# Report hazard ratios with 95% CI

# Extension: Fit a stratified Cox model by sex
```

### Step 4: Bayesian Survival Analysis (Checkpoint 4)
```julia
using Turing

@model function bayesian_survival(times, events, treatment, age)
    # Priors
    β_trt ~ Normal(0, 1)      # log hazard ratio for treatment
    β_age ~ Normal(0, 0.1)    # log hazard ratio per year of age
    λ₀ ~ Gamma(2, 0.1)        # baseline hazard
    shape ~ Gamma(2, 1)        # Weibull shape
    
    for i in eachindex(times)
        scale_i = λ₀ * exp(β_trt * treatment[i] + β_age * (age[i] - 60))
        dist = Weibull(shape, 1/scale_i)
        
        if events[i]
            times[i] ~ dist
        else
            # Censored: contribute survival probability
            Turing.@addlogprob! logccdf(dist, times[i])
        end
    end
end

# Run MCMC with NUTS
chain = sample(bayesian_survival(trial_data.time, trial_data.event,
               trial_data.treatment, trial_data.age), NUTS(), 2000)

# [FIGURE: Posterior distribution of hazard ratio with 95% credible interval]
# [FIGURE: Trace plots and R-hat diagnostics]
```

### Step 5: Sensitivity Analysis & Reporting (Checkpoint 5)
```julia
# 1. Sensitivity to unmeasured confounding (E-value)
# 2. Multiple testing correction if multiple endpoints
# 3. Subgroup analyses by age and sex
# 4. Compare frequentist vs Bayesian estimates
# 5. Generate publication-ready table of results
```

## Extensions
- Add time-varying covariates
- Implement competing risks analysis
- Add interim analysis with alpha spending function
- Perform propensity score analysis on a modified (non-randomized) version

---

# Lab 2: Discover Governing Equations from Noisy Data
**Tracks:** SCIML-002 (Neural ODEs), XCUT-001 (UQ), XCUT-002 (Inverse Problems), SCIML-004 (AD)

## Objective
Given noisy trajectory data from an unknown dynamical system, use Universal
Differential Equations (UDEs) to discover the governing equations, quantify
uncertainty, and compare to SINDy (Sparse Identification of Nonlinear Dynamics).

## Scaffolded Steps

### Step 1: Generate Ground Truth Data
```julia
using DifferentialEquations, Lux, ComponentArrays, Optimization, OptimizationOptimisers
using Random, ForwardDiff

# True system: Lorenz attractor (unknown to the learner initially)
function lorenz!(du, u, p, t)
    σ, ρ, β = 10.0, 28.0, 8/3
    du[1] = σ * (u[2] - u[1])
    du[2] = u[1] * (ρ - u[3]) - u[2]
    du[3] = u[1] * u[2] - β * u[3]
end

u0 = [1.0, 0.0, 0.0]
tspan = (0.0, 5.0)
prob = ODEProblem(lorenz!, u0, tspan)
sol = solve(prob, Tsit5(), saveat=0.02)

# Add measurement noise
noise_level = 0.5
data = Array(sol) .+ noise_level .* randn(size(Array(sol)))
```

### Step 2: Build a Universal Differential Equation
```julia
# Replace the unknown right-hand side with a neural network
nn = Lux.Chain(
    Lux.Dense(3, 64, tanh),
    Lux.Dense(64, 64, tanh),
    Lux.Dense(64, 3)
)
rng = Random.default_rng()
ps, st = Lux.setup(rng, nn)

function ude!(du, u, p, t)
    û = nn(u, p, st)[1]
    du .= û
end

# Train using multiple shooting
# [FIGURE: Training loss curve showing convergence]
# [FIGURE: Predicted vs true trajectories]
```

### Step 3: SINDy Comparison
```julia
# Implement Sparse Identification of Nonlinear Dynamics
# Build library of candidate functions: 1, x, y, z, x², xy, xz, y², yz, z², ...
# Use sequential thresholded least squares to find sparse coefficients
# Compare discovered equations to true Lorenz system
```

### Step 4: Uncertainty Quantification
```julia
# Use ensemble of trained UDEs or Bayesian neural ODE to quantify
# epistemic uncertainty in the discovered dynamics
# [FIGURE: Trajectory predictions with uncertainty bands]
```

### Step 5: Robustness Analysis
```julia
# Test discovery accuracy vs:
# - Noise level (0.1 to 2.0)
# - Amount of training data (50 to 500 points)
# - Trajectory length
# - Initial condition diversity
# [FIGURE: Phase diagram of discovery success vs noise and data quantity]
```

---

# Lab 3: Spatial Disease Spread Prediction
**Tracks:** BIOS-008 (Spatial Epi), GEO-002 (Point Processes), ABM-001 (ABM), BIOS-007 (Epidemic)

## Objective
Build a multi-scale model of disease spread: ODE at the population level,
agent-based at the individual level, and spatial point process for case locations.
Compare predictions and computational trade-offs.

## Steps
1. Simulate county-level SIR dynamics with spatial coupling (metapopulation ODE)
2. Implement agent-based SIR on a contact network using Agents.jl
3. Fit a log-Gaussian Cox process to observed case locations
4. Compare ODE vs ABM epidemic curves; identify where ODE approximation breaks down
5. Predict spatial hotspots using kriging on case rates

---

# Lab 4: Blood Flow in a Stenosed Artery
**Tracks:** PHYS-001 (Continuum Mech), PHYS-002 (Fluids), PHYS-003 (Biomechanics), CORE-007 (PDEs)

## Objective
Solve the Navier-Stokes equations in a 2D channel with a stenosis (narrowing),
compute wall shear stress, and analyze the relationship between stenosis severity
and flow separation / recirculation zones.

## Steps
1. Set up 2D domain with parameterized stenosis geometry
2. Solve steady Stokes flow (low Re) using Ferrite.jl finite elements
3. Extend to Navier-Stokes with Newton iteration for moderate Re
4. Compute wall shear stress distribution along the vessel wall
5. Parameter study: stenosis severity (20%–80%) vs recirculation zone length
6. Compare to Poiseuille flow analytical solution in the unobstructed sections

---

# Lab 5: Bayesian Model Selection for Population Dynamics
**Tracks:** CORE-008 (Bayesian), POP-001 (Deterministic), POP-002 (Stochastic), XCUT-001 (UQ)

## Objective
Given noisy population time series data, fit multiple competing models
(exponential, logistic, Gompertz, theta-logistic, Allee effect), compute
Bayesian model evidence via bridge sampling, and perform Bayesian model averaging.

## Steps
1. Generate synthetic data from a known model with realistic noise
2. Implement all five growth models as ODE systems
3. Fit each model using Turing.jl with weakly informative priors
4. Compute WAIC and LOO-CV for each model
5. Estimate marginal likelihood via bridge sampling for Bayes factors
6. Perform Bayesian model averaging for prediction with model uncertainty
7. Visualize: posterior predictive distributions under each model and the BMA ensemble

---

# Implementation Notes

Each lab should be implemented as a Pluto.jl notebook with:
- Interactive sliders for key parameters
- Automatic checkpoints that verify intermediate results
- "Hint" cells that can be toggled (initially hidden)
- Extension challenges for advanced students
- Estimated completion time: 4–8 hours per lab

All labs use Julia exclusively with packages from the curriculum.

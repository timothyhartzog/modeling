# Dynamic Clinical Medicine: Modeling Diagnosis, Prognosis, and Risk with Ordinary and Partial Differential Equations

## Textbook Overview

This is a comprehensive, graduate-level textbook that presents a paradigm shift in clinical medicine: replacing static biostatistical risk calculators, diagnostic scoring systems, and prognostic models with continuous-time dynamical systems built from ordinary and partial differential equations (ODEs and PDEs).

**Central Thesis:** Clinical medicine currently relies on static, time-invariant risk scores (Framingham, APACHE, SOFA, Wells, CHA₂DS₂-VASc, etc.) that collapse continuous disease processes into categorical risk strata. These tools ignore physiological feedback loops, cannot model treatment response trajectories, and provide single-timepoint snapshots of fundamentally dynamic processes. ODE/PDE-based mechanistic models offer explicit representation of feedback, patient-specific parameter estimation, trajectory prediction, and mechanistic interpretability.

**Target Audience:** Clinician-scientists, biomedical engineering graduate students, clinical informaticians, and quantitative-minded physicians. Assumes calculus exposure but builds ODE/PDE competence from first principles.

## Textbook Structure (36 Chapters)

### Part I: Foundations (Chapters 1–5)
1. The Case Against Static Risk: Why Clinical Medicine Needs Dynamical Systems
2. Mathematical Foundations I: Ordinary Differential Equations for Clinicians
3. Mathematical Foundations II: Partial Differential Equations for Clinical Modeling
4. Numerical Methods for Clinical ODEs and PDEs
5. Parameter Estimation and Patient-Specific Model Calibration

### Part II: Pharmacological Modeling (Chapters 6–7)
6. Pharmacokinetic Modeling: From Compartments to Physiologically-Based Models
7. Pharmacodynamic Modeling: Linking Drug Concentrations to Clinical Effects

### Part III: Organ System Physiology (Chapters 8–13)
8. Cardiovascular Hemodynamics: ODE Models of Pressure, Flow, and Volume
9. Cardiac Electrophysiology: From Ion Channel ODEs to Arrhythmia Prediction
10. Respiratory Physiology: Gas Exchange and Ventilator Management Models
11. Renal Physiology: Fluid, Electrolyte, and Acid-Base ODE Models
12. Glucose-Insulin Dynamics: From Minimal Models to Artificial Pancreas Control
13. Infectious Disease Dynamics: Compartmental Epidemiological Models

### Part IV: Disease Process Modeling (Chapters 14–25)
14. Tumor Growth and Cancer Treatment Modeling
15. Sepsis as a Dynamical System: Replacing SIRS/qSOFA with Trajectory Models
16. Hematological Dynamics: Coagulation Cascades, Hematopoiesis, and Anemia
17. Neurological Dynamics: Seizure Prediction, Consciousness, and Neurodegeneration
18. Endocrine Dynamics: Hormonal Axes as Feedback Control Systems
19. Hepatic Physiology and Liver Disease Progression Models
20. Neonatal and Pediatric Physiological Modeling
21. Wound Healing and Tissue Repair: Reaction-Diffusion Models
22. Bone and Musculoskeletal Dynamics: Remodeling, Fracture Healing, and Osteoporosis
23. Immunological Dynamics: Autoimmunity, Transplant Rejection, and Immunotherapy
24. Gastrointestinal Dynamics: Motility, Absorption, and Microbiome Models
25. Thermal Physiology: Fever, Hypothermia, and Targeted Temperature Management

### Part V: Clinical Applications (Chapters 26–28)
26. Dynamic Diagnostic Models: Replacing Static Sensitivity/Specificity
27. Dynamic Prognostic Models: Replacing Cox Regression with Mechanistic Survival
28. Optimal Control Theory for Treatment Optimization

### Part VI: Validation and Implementation (Chapters 29–35)
29. Sensitivity Analysis, Uncertainty Quantification, and Model Validation
30. The Clinical Digital Twin: Patient-Specific Simulation at the Bedside
31. Cardiovascular Risk Prediction: From Framingham to Hemodynamic Trajectories
32. Critical Care Scoring Systems Reimagined: APACHE, SOFA, MEWS as Trajectories
33. Machine Learning Meets Mechanistic Models: Hybrid and Physics-Informed Approaches
34. Software Implementation: Building Clinical ODE/PDE Models in Julia, Python, and R
35. Regulatory Science, Clinical Validation, and Ethical Considerations

### Part VII: Vision (Chapter 36)
36. The Future of Dynamic Clinical Medicine: A Research Agenda

## Generation Pipeline

This textbook uses the **batch-textbook** skill for automated chapter generation:

```bash
# Generate all chapters
node scripts/run-batch.js

# Generate a single chapter
node scripts/run-batch.js --chapter ch01

# Resume after interruption
node scripts/run-batch.js --resume
```

## Technical Specifications

- **Total chapters:** 36
- **Target word count:** ~475,000 words (average ~13,200 per chapter)
- **Output format:** DOCX (one file per chapter) + Markdown source
- **Style guide:** Academic (peer-reviewed journal quality)
- **References:** Minimum 10 per chapter (APA format)
- **Software examples:** Julia (DifferentialEquations.jl, ModelingToolkit.jl), Python (SciPy, FEniCS), R (deSolve)

## Static Calculators Replaced

| Static Calculator | Chapter | Dynamic Replacement |
|---|---|---|
| Framingham Risk Score | 31 | Atherosclerotic plaque progression ODE |
| ASCVD Pooled Cohort | 31 | Multi-factor hemodynamic trajectory |
| CHA₂DS₂-VASc | 31 | LAA flow velocity + thrombus kinetics ODE |
| HEART Score | 31 | Troponin kinetics + coronary flow ODE |
| APACHE II/III/IV | 32 | Multi-organ coupled ODE system |
| SOFA Score | 15, 32 | Organ subsystem trajectory ODEs |
| MEWS/NEWS/PEWS | 32 | Continuous monitoring trajectory models |
| Wells Score (PE) | 26 | Sequential Bayesian diagnostic ODE |
| Bhutani Nomogram | 19, 20 | Bilirubin kinetics compartmental model |
| Rumack-Matthew | 19 | PBPK + glutathione depletion ODE |
| GFR (CKD-EPI) | 11 | Glomerular filtration Starling forces ODE |
| Winter's Formula | 11 | Stewart acid-base transport ODEs |
| Kt/V (Dialysis) | 11 | Double-pool urea kinetics ODE |
| DKA Protocol | 12 | Glucose-ketone-pH coupled ODE + control |
| Glasgow Coma Scale | 17 | Neural mass model trajectory |
| MELD Score | 19 | Hepatic function ODE trajectory |
| FRAX | 22 | Bone remodeling ODE trajectory |
| TNM Staging | 14 | Tumor growth + treatment response ODE |
| QTc Risk Scoring | 9 | Patient-specific action potential simulation |
| SBT Criteria | 10 | Respiratory muscle fatigue trajectory ODE |
| Rockall/Blatchford | 24 | GI hemodynamic trajectory model |
| DIC Scoring | 16 | Coagulation cascade ODE trajectory |

## Author

Timothy Hartzog, MD — Board-certified pediatrician, clinical informatician, and computational medicine researcher.

## Repository

`timothyhartzog/modeling` — Julia batch textbook generation pipeline

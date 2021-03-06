__precompile__()

module OrbitTomography

using LinearAlgebra
using Statistics
using SparseArrays
using Distributed
using Printf
import Base.Iterators: partition

using EFIT
using Equilibrium
using GuidingCenterOrbits
using HDF5
using JLD2, FileIO
using Clustering
using Images
using StatsBase
using FillArrays
using ProgressMeter
using NearestNeighbors
using SparseArrays
using StaticArrays
using NonNegLeastSquares
using HCubature
using Interpolations
using Distributed
using Optim
using Sobol
using ForwardDiff
using Roots
import IterTools: nth

const S3 = SVector{3}
const S4 = SVector{4}
const S33 = SMatrix{3,3}
const S44 = SMatrix{4,4}

const e0 = 1.60217733e-19 # Coulombs / Joules
const mu0 = 4*pi*1e-7 # N/A^2
const c0 = 2.99792458e8 # m/s

const mass_u = 1.6605402e-27 # kg
const e_amu = 5.48579909070e-4 # amu
const H1_amu = 1.007276466879 # amu
const H2_amu = 2.0141017778 # amu
const H3_amu = 3.01550071632 # amu
const He3_amu = 3.01602931914 # amu
const B5_amu = 10.81 # amu
const C6_amu = 12.011 # amu

include("polyharmonic.jl")
export PolyharmonicSpline

include("spectra.jl")
export InstrumentalResponse, kernel
export ExperimentalSpectra, TheoreticalSpectra

include("io.jl")
export FIDASIMSpectra
export AbstractDistribution, FIDASIMGuidingCenterFunction, FIDASIMGuidingCenterParticles, FIDASIMFullOrbitParticles
export read_fidasim_distribution, write_fidasim_distribution
export FIDASIMBeamGeometry, FIDASIMSpectraGeometry, FIDASIMNPAGeometry, write_fidasim_geometry
export FIDASIMPlasmaParameters

include("fidasim_utils.jl")
export split_spectra, merge_spectra, apply_instrumental!, merge_spectra_geometry
export split_particles, fbm2mc
export impurity_density, ion_density

include("orbits.jl")
export OrbitGrid, orbit_grid, segment_orbit_grid,combine_orbits, fbm2orbit, mc2orbit
export map_orbits, bin_orbits
export write_orbit_grid, read_orbit_grid
export orbit_index, orbit_matrix
export OrbitSpline

include("covariance.jl")
export epr_cov
export RepeatedBlockDiagonal, ep_cov, eprz_cov,transform_eprz_cov, eprz_kernel
export get_covariance, get_correlation, get_correlation_matrix, get_covariance_matrix
export get_global_covariance, get_global_covariance_matrix

include("weights.jl")
export AbstractWeight, FIDAOrbitWeight

include("tomography.jl")
export OrbitSystem, lcurve_point, lcurve, marginal_loglike, optimize_alpha!, estimate_rtol, optimize_parameters, inv_chol, solve

include("transforms.jl")
export EPDensity, local_distribution, RZDensity, rz_profile, EPRZDensity, eprz_distribution

include("analytic.jl")
export slowing_down, bimaxwellian, maxwellian

end # module

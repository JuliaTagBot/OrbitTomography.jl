struct FIDASIMSpectra{T<:Real}
    nchan::Int
    nlambda::Int
    lambda::Vector{T}
    full::Union{Zeros{T,2},Matrix{T}}
    half::Union{Zeros{T,2},Matrix{T}}
    third::Union{Zeros{T,2},Matrix{T}}
    dcx::Union{Zeros{T,2},Matrix{T}}
    halo::Union{Zeros{T,2},Matrix{T}}
    cold::Union{Zeros{T,2},Matrix{T}}
    fida::Union{Zeros{T,2},Zeros{T,3},Matrix{T},Array{T,3}}
    pfida::Union{Zeros{T,2},Zeros{T,3},Matrix{T},Array{T,3}}
end

function FIDASIMSpectra(fname::String)
    isfile(fname) || error("File does not exist")

    f = h5open(fname)
    nchan = Int(read(f["nchan"]))
    lambda = read(f["lambda"])
    nlam = length(lambda)

    full = "full" in names(f) ? read(f["full"]) : Zeros(nlam,nchan)
    half = "half" in names(f) ? read(f["half"]) : Zeros(nlam,nchan)
    third = "third" in names(f) ? read(f["third"]) : Zeros(nlam,nchan)
    dcx = "dcx" in names(f) ? read(f["dcx"]) : Zeros(nlam,nchan)
    halo = "halo" in names(f) ? read(f["halo"]) : Zeros(nlam,nchan)
    cold = "cold" in names(f) ? read(f["cold"]) : Zeros(nlam,nchan)
    fida = "fida" in names(f) ? read(f["fida"]) : Zeros(nlam,nchan)
    pfida = "pfida" in names(f) ? read(f["pfida"]) : Zeros(size(fida))

    return FIDASIMSpectra(Int(nchan),Int(nlam),lambda,full,half,third,dcx,halo,cold,fida,pfida)
end

function Base.show(io::IO, s::FIDASIMSpectra)
    println(io, "FIDASIMSpectra")
    println(io, "  nchan   = $(s.nchan)")
    println(io, "  nlambda = $(s.nlambda)")
end

function split_spectra(s::FIDASIMSpectra)
    length(size(s.fida)) == 2 && return s

    nlambda, nchan, nclass = size(s.fida)

    ss = Array{typeof(s)}(nclass)
    for i=1:nclass
        sss = FIDASIMSpectra(nchan, nlambda, s.lambda, s.full, s.half, s.third,
                             s.dcx, s.halo, s.cold, s.fida[:,:,i], s.pfida[:,:,i])
        ss[i] = sss
    end

    return ss
end

function Base.hcat(x::Zeros{T,2}...) where T <: Real
    all(xx -> xx.size[1] == x[1].size[1], x) || throw(ArgumentError("mismatch in dimension 1"))
    n = sum(xx.size[2] for xx in x)

    return Zeros(x[1].size[1],n)
end

function merge_spectra(s::FIDASIMSpectra...)
    all(x -> length(size(x.fida)) == length(size(s[1].fida)), s) || error("Incompatible fida sizes")
    all(x -> length(x.lambda) == length(s[1].lambda), s) || error("Incompatible lambda sizes")
    all(x -> x.lambda[1] == s[1].lambda[1], s) || error("Incompatible lambda min")
    all(x -> x.lambda[end] == s[1].lambda[end], s) || error("Incompatible lambda max")

    nchan = sum(ss.nchan for ss in s)
    lambda = s[1].lambda
    nlambda = s[1].nlambda

    full = hcat((ss.full for ss in s)...)
    half = hcat((ss.half for ss in s)...)
    third = hcat((ss.third for ss in s)...)
    dcx = hcat((ss.dcx for ss in s)...)
    halo = hcat((ss.halo for ss in s)...)
    cold = hcat((ss.cold for ss in s)...)
    fida = hcat((ss.fida for ss in s)...)
    pfida = hcat((ss.pfida for ss in s)...)

    return FIDASIMSpectra(nchan, nlambda, lambda, full, half, third, dcx, halo, cold, fida, pfida)
end

function TheoreticalSpectra(S::FIDASIMSpectra, stype::Symbol, ichan::Int, iclass::Int=1)
    spec = getfield(S,stype)
    TheoreticalSpectra(S.lambda,spec[:,ichan,iclass])
end

function apply_instrumental!(s::FIDASIMSpectra,instr::Vector,dL::Vector)
    ni = length(instr)
    if ni != s.nchan
        error("Instrumental has wrong shape")
    end

    for i=1:s.nchan
        k = kernel(s.lambda,instr[i],dL[i])
        length(eachindex(k)) == 0 && continue
        !(typeof(s.full) <: Zeros)  && (s.full[:,i]  .= imfilter(s.full[:,i], k))
        !(typeof(s.half) <: Zeros)  && (s.half[:,i]  .= imfilter(s.half[:,i], k))
        !(typeof(s.third) <: Zeros) && (s.third[:,i] .= imfilter(s.third[:,i], k))
        !(typeof(s.dcx) <: Zeros)   && (s.dcx[:,i]   .= imfilter(s.dcx[:,i], k))
        !(typeof(s.halo) <: Zeros)  && (s.halo[:,i]  .= imfilter(s.halo[:,i], k))
        !(typeof(s.cold) <: Zeros)  && (s.cold[:,i]  .= imfilter(s.cold[:,i], k))
        !(typeof(s.fida) <: Zeros)  && (s.fida[:,i]  .= imfilter(s.fida[:,i], k))
        !(typeof(s.pfida) <: Zeros) && (s.pfida[:,i] .= imfilter(s.pfida[:,i], k))
    end
end

function apply_instrumental!(s::FIDASIMSpectra, i)
    instr = fill(i, s.nchan)
    dL = fill(abs(s.lambda[2]-s.lambda[1]),s.nchan)
    apply_instrumental!(s, instr, dL)
end

abstract type AbstractDistribution end

struct FIDASIMGuidingCenterFunction <: AbstractDistribution
    nr::Int
    nz::Int
    nenergy::Int
    npitch::Int
    r::Vector{Float64}
    z::Vector{Float64}
    energy::Vector{Float64}
    pitch::Vector{Float64}
    denf::Matrix{Float64}
    f::Array{Float64,4}
end

function FIDASIMGuidingCenterFunction(f::HDF5.HDF5File)

    nr = read(f["nr"])
    nz = read(f["nz"])
    nenergy = read(f["nenergy"])
    npitch = read(f["npitch"])

    energy = read(f["energy"])
    pitch = read(f["pitch"])
    r = read(f["r"])
    z = read(f["z"])
    denf = read(f["denf"])
    dist = read(f["f"])

    return FIDASIMGuidingCenterFunction(nr,nz,nenergy,npitch,r,z,energy,pitch,denf,dist)
end

function Base.show(io::IO, s::FIDASIMGuidingCenterFunction)
    println(io, "FIDASIMGuidingCenterFunction")
end

struct FIDASIMGuidingCenterParticles <: AbstractDistribution
    npart::Int
    nclass::Int
    class::Vector{Int}
    weight::Vector{Float64}
    r::Vector{Float64}
    z::Vector{Float64}
    energy::Vector{Float64}
    pitch::Vector{Float64}
end

function FIDASIMGuidingCenterParticles(f::HDF5.HDF5File)

    npart = read(f["nparticle"])
    nclass = read(f["nclass"])
    class = read(f["class"])
    weight = read(f["weight"])

    energy = read(f["energy"])
    pitch = read(f["pitch"])
    r = read(f["r"])
    z = read(f["z"])

    return FIDASIMGuidingCenterParticles(npart,nclass,class,weight,r,z,energy,pitch)
end

function Base.show(io::IO, s::FIDASIMGuidingCenterParticles)
    println(io, "FIDASIMGuidingCenterParticles")
    println(io, "  nparticles = $(s.npart)")
end

struct FIDASIMFullOrbitParticles <: AbstractDistribution
    npart::Int
    nclass::Int
    class::Vector{Int}
    weight::Vector{Float64}
    r::Vector{Float64}
    z::Vector{Float64}
    vr::Vector{Float64}
    vt::Vector{Float64}
    vz::Vector{Float64}
end

function FIDASIMFullOrbitParticles(f::HDF5.HDF5File)

    npart = read(f["nparticle"])
    nclass = read(f["nclass"])
    class = read(f["class"])
    weight = read(f["weight"])

    r = read(f["r"])
    z = read(f["z"])
    vr = read(f["vr"])
    vt = read(f["vt"])
    vz = read(f["vz"])

    return FIDASIMFullOrbitParticles(npart,nclass,class,weight,r,z,vr,vt,vz)
end

function Base.show(io::IO, s::FIDASIMFullOrbitParticles)
    println(io, "FIDASIMFullOrbitParticles")
    println(io, "  nparticles = $(s.npart)")
end

function read_fidasim_distribution(filename::String)
    isfile(filename) || error("File does not exist")

    f = h5open(filename)
    dtype = read(f["type"])

    if dtype == 1
        d = FIDASIMGuidingCenterFunction(f)
    elseif dtype == 2
        d = FIDASIMGuidingCenterParticles(f)
    elseif dtype == 3
        d = FIDASIMFullOrbitParticles(f)
    else
        error("Unknown distribution type")
    end
    close(f)

    return d
end

function write_fidasim_distribution(M::AxisymmetricEquilibrium, orbits; filename="orbits.h5",time=0.0)

    norbs = length(orbits)
    energy = Float64[]
    pitch = Float64[]
    r = Float64[]
    z = Float64[]
    weight = Float64[]
    class = Int16[]
    tau_t = Float64[]
    tau_p = Float64[]
    energy_c = Float64[]
    pitch_c = Float64[]
    r_c = Float64[]
    z_c = Float64[]

    for (i,o) in enumerate(orbits)
        append!(energy,o.path.energy)
        append!(pitch, M.sigma*o.path.pitch)
        append!(r, o.path.r*100)
        append!(z, o.path.z*100)
        append!(class, fill(Int16(i),length(o.path.r)))
        append!(weight, o.path.dt.*(1e19/sum(o.path.dt)))
        push!(tau_t, o.tau_t)
        push!(tau_p, o.tau_p)
        if isa(o.coordinate,EPRCoordinate)
            push!(energy_c, o.coordinate.energy)
            push!(pitch_c, o.coordinate.pitch)
            push!(r_c, o.coordinate.r)
            push!(z_c, o.coordinate.z)
        end
    end
    npart = length(energy)

    h5open(filename,"w") do file
        if length(energy_c) == norbs
            file["energy_c","shuffle",(),"chunk",(norbs),"compress",4] = energy_c
            file["pitch_c","shuffle",(),"chunk",(norbs),"compress",4] = pitch_c
            file["r_c","shuffle",(),"chunk",(norbs),"compress",4] = r_c
            file["z_c","shuffle",(),"chunk",(norbs),"compress",4] = z_c
        end
        file["tau_p","shuffle",(),"chunk", (norbs),"compress", 4] = tau_p
        file["tau_t","shuffle",(),"chunk", (norbs),"compress", 4] = tau_t
        file["data_source"] = "Generated from GEQDSK"
        file["type"] = 2
        file["nclass"] = norbs
        file["nparticle"] = npart
        file["time"] = time
        file["energy", "shuffle",(), "chunk", (npart),"compress", 4] = energy
        file["pitch","shuffle",(), "chunk", (npart),"compress", 4] = pitch
        file["r","shuffle",(), "chunk", (npart),"compress", 4] = r
        file["z","shuffle",(), "chunk", (npart),"compress", 4] = z
        file["class","shuffle",(), "chunk", (npart),"compress", 4] = class
        file["weight","shuffle",(), "chunk", (npart),"compress", 4] = weight
    end
    nothing
end

function split_particles(d::FIDASIMGuidingCenterParticles)

    d.nclass <= 1 && return d

    darr = Array{typeof(d)}(d.nclass)
    for c = 1:d.nclass
        w = d.class .== c
        npart = sum(w)
        dd = FIDASIMGuidingCenterParticles(npart,1,fill(c,npart),
                                           d.weight[w], d.r[w], d.z[w],
                                           d.energy[w],d.pitch[w])
        darr[c] = dd
    end

    return darr
end

function split_particles(d::FIDASIMFullOrbitParticles)

    d.nclass <= 1 && return d

    darr = Array{typeof(d)}(d.nclass)
    for c = 1:d.nclass
        w = d.class .== c
        npart = sum(w)
        dd = FIDASIMFullOrbitParticles(npart,1,fill(1,npart),
                                       d.weight[w], d.r[w], d.z[w],
                                       d.vr[w], d.vt[w], d.vz[w])
        darr[c] = dd
    end

    return darr
end

struct FIDASIMBeamGeometry
    src::Vector{Float64}
    axis::Vector{Float64}
    shape::Int
    widy::Float64
    widz::Float64
    divy::Vector{Float64}
    divz::Vector{Float64}
    focy::Float64
    focz::Float64
    naperture::Int
    ashape::Vector{Int}
    awidy::Vector{Float64}
    awidz::Vector{Float64}
    aoffy::Vector{Float64}
    aoffz::Vector{Float64}
    adist::Vector{Float64}
end

function FIDASIMBeamGeometry(filename::String)
    isfile(filename) || error("File does not exist")

    f = h5open(filename)
    if !("nbi" in names(f))
        close(f)
        error("Beam geometry not in file")
    end

    src = read(f["nbi"]["src"])
    axis = read(f["nbi"]["axis"])
    shape = Int(read(f["nbi"]["shape"]))
    widy = read(f["nbi"]["widy"])
    widz = read(f["nbi"]["widz"])
    divy = read(f["nbi"]["divy"])
    divz = read(f["nbi"]["divz"])
    focy = read(f["nbi"]["focy"])
    focz = read(f["nbi"]["focz"])
    naperture = Int(read(f["nbi"]["naperture"]))
    if naperture > 0
        ashape = Int.(read(f["nbi"]["ashape"]))
        awidy = read(f["nbi"]["awidy"])
        awidz = read(f["nbi"]["awidz"])
        aoffy = read(f["nbi"]["aoffy"])
        aoffz = read(f["nbi"]["aoffz"])
        adist = read(f["nbi"]["adist"])
    else
        ashape = Int[]
        awidy = Float64[]
        awidz = Float64[]
        aoffy = Float64[]
        aoffz = Float64[]
        adist = Float64[]
    end
    close(f)

    return FIDASIMBeamGeometry(src,axis,shape,widy,widz,divy,divz,focy,focz,
                               naperture, ashape, awidy, awidz, aoffy, aoffz, adist)
end

function Base.show(io::IO, s::FIDASIMBeamGeometry)
    println(io, "FIDASIMBeamGeometry")
end

struct FIDASIMSpectraGeometry
    nchan::Int
    system::String
    id::Vector{String}
    radius::Vector{Float64}
    lens::Matrix{Float64}
    axis::Matrix{Float64}
    spot_size::Vector{Float64}
    sigma_pi::Vector{Float64}
end

function FIDASIMSpectraGeometry(filename::String)
    isfile(filename) || error("File does not exist")

    f = h5open(filename)
    if !("spec" in names(f))
        close(f)
        error("Spectra geometry not in file")
    end

    nchan = Int(read(f["spec"]["nchan"]))
    system = read(f["spec"]["system"])
    id = read(f["spec"]["id"])
    radius = read(f["spec"]["radius"])
    lens = read(f["spec"]["lens"])
    axis = read(f["spec"]["axis"])
    spot_size = read(f["spec"]["spot_size"])
    sigma_pi = read(f["spec"]["sigma_pi"])

    close(f)

    return FIDASIMSpectraGeometry(nchan,system,id,radius,lens,axis,spot_size,sigma_pi)
end

function Base.show(io::IO, s::FIDASIMSpectraGeometry)
    println(io, "FIDASIMSpectraGeometry")
    println(io, "  nchan: $(s.nchan)")
    println(io, "  system: "*s.system)
end

function merge_spectra_geometry(s::FIDASIMSpectraGeometry...)
    length(s) == 1 && return s

    nchan = sum(ss.nchan for ss in s)
    system = join((ss.system for ss in s),"; ")
    id = vcat((ss.id for ss in s)...)
    radius = vcat((ss.radius for ss in s)...)
    lens = hcat((ss.lens for ss in s)...)
    axis = hcat((ss.axis for ss in s)...)
    spot_size = vcat((ss.spot_size for ss in s)...)
    sigma_pi = vcat((ss.sigma_pi for ss in s)...)

    return FIDASIMSpectraGeometry(nchan,system,id,radius,lens,axis,spot_size,sigma_pi)
end

struct FIDASIMNPAGeometry
    nchan::Int
    system::String
    id::Vector{String}
    radius::Vector{Float64}
    a_shape::Vector{Int}
    d_shape::Vector{Int}
    a_cent::Matrix{Float64}
    a_redge::Matrix{Float64}
    a_tedge::Matrix{Float64}
    d_cent::Matrix{Float64}
    d_redge::Matrix{Float64}
    d_tedge::Matrix{Float64}
end

function FIDASIMNPAGeometry(filename::String)
    isfile(filename) || error("File does not exist")

    f = h5open(filename)
    if !("npa" in names(f))
        close(f)
        error("NPA geometry not in file")
    end

    nchan = Int(read(f["npa"]["nchan"]))
    system = read(f["npa"]["system"])
    id = read(f["npa"]["id"])
    radius = read(f["npa"]["radius"])
    a_shape = Int.(read(f["npa"]["a_shape"]))
    d_shape = Int.(read(f["npa"]["d_shape"]))
    a_cent = read(f["npa"]["a_cent"])
    a_redge = read(f["npa"]["a_redge"])
    a_tedge = read(f["npa"]["a_tedge"])
    d_cent = read(f["npa"]["d_cent"])
    d_redge = read(f["npa"]["d_redge"])
    d_tedge = read(f["npa"]["d_tedge"])

    close(f)

    return FIDASIMNPAGeometry(nchan, system, id, radius,
                              a_shape, d_shape,
                              a_cent, a_redge, a_tedge,
                              d_cent, d_redge, d_tedge)
end

function Base.show(io::IO, s::FIDASIMNPAGeometry)
    println(io, "FIDASIMNPAGeometry")
    println(io, "  nchan: $(s.nchan)")
    println(io, "  system: "*s.system)
end
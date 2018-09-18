struct OrbitGrid{T}
    energy::AbstractVector{T}
    pitch::AbstractVector{T}
    r::AbstractVector{T}
    counts::Vector{Int}
    orbit_index::Array{Int,3}
    class::Array{Symbol,3}
    tau_p::Array{T,3}
    tau_t::Array{T,3}
end

function Base.show(io::IO, og::OrbitGrid)
    print(io, "OrbitGrid: $(length(og.energy))×$(length(og.pitch))×$(length(og.r))")
end

function orbit_grid(M::AxisymmetricEquilibrium, wall, eo::AbstractVector, po::AbstractVector, ro::AbstractVector;
                    nstep=12000, tmax=1200.0, dl=0.0, store_path=false)

    nenergy = length(eo)
    npitch = length(po)
    nr = length(ro)

    orbit_index = zeros(Int,nenergy,npitch,nr)
    class = fill(:incomplete,(nenergy,npitch,nr))
    tau_t = zeros(Float64,nenergy,npitch,nr)
    tau_p = zeros(Float64,nenergy,npitch,nr)

    norbs = nenergy*npitch*nr
    subs = CartesianIndices((nenergy,npitch,nr))
    orbs = @distributed (vcat) for i=1:norbs
        ie,ip,ir = Tuple(subs[i])
        c = EPRCoordinate(M,eo[ie],po[ip],ro[ir])
        try
            o = get_orbit(M, c, nstep=nstep, tmax=tmax)
        catch
            o = Orbit(EPRCoordinate(),:incomplete)
        end

        if o.class == :incomplete || o.class == :degenerate || hits_wall(o,wall)
            o = Orbit(o.coordinate,:incomplete)
        elseif store_path
            if dl > 0.0
                rpath = down_sample(o.path,mean_dl=dl)
                o = Orbit(o.coordinate,o.class,o.tau_p,o.tau_t,rpath)
            end
        else
            o = Orbit(o.coordinate,o.class,o.tau_p,o.tau_t,OrbitPath(typeof(o.tau_p)))
        end
        o
    end
    for i=1:norbs
        class[subs[i]] = orbs[i].class
        tau_p[subs[i]] = orbs[i].tau_p
        tau_t[subs[i]] = orbs[i].tau_t
    end

    grid_index = filter(i -> orbs[i].class != :incomplete, 1:norbs)
    orbs = filter(x -> x.class != :incomplete, orbs)
    norbs = length(orbs)
    orbit_index[grid_index] = 1:norbs

    return orbs, OrbitGrid(eo,po,ro,fill(1,norbs),orbit_index,class,tau_p,tau_t)

end

function segment_orbit_grid(M::AxisymmetricEquilibrium, orbit_grid::OrbitGrid, orbits::Vector;
                        norbits=1000, dl=0.0, nstep = 12000, tmax=1200.0, combine=(length(orbits[1].path) != 0))

    eo = orbit_grid.energy
    po = orbit_grid.pitch
    ro = orbit_grid.r

    nenergy = length(eo)
    npitch = length(po)
    nr = length(ro)
    norbs = length(orbits)

    e_range = extrema(eo)
    p_range = extrema(po)
    r_range = extrema(ro)
    orbs_index = zeros(Int,norbs)
    for i = 1:length(orbit_grid.orbit_index)
        ii = orbit_grid.orbit_index[i]
        ii == 0 && continue
        orbs_index[ii] != 0 && continue
        orbs_index[ii] = i
    end

    orbit_index = zeros(Int,nenergy,npitch,nr)

    norm = abs.([-(e_range...), -(p_range...), -(r_range...)])
    mins = [e_range[1],p_range[1],r_range[1]]
    oclasses = [:potato, :stagnation, :trapped, :co_passing, :ctr_passing]

    orbit_counts = Dict{Symbol,Int}(o=>count(x -> x.class == o, orbits)
                                    for o in oclasses)

    nclusters = 0
    orbs = eltype(orbits)[]
    orbit_num = 0
    for oc in oclasses
        nk = max(Int(ceil(norbits*orbit_counts[oc]/norbs)),1)
        if (nclusters + nk) > norbits
            nk = norbits - nclusters
        end
        nk == 0 && continue

        inds_oc = findall([o.class == oc for o in orbits])
        coords = hcat((([o.coordinate.energy, o.coordinate.pitch, o.coordinate.r] .- mins)./norm
                       for o in orbits if o.class == oc)...)

        if nk == 1
            if !combine
                c = coords .* norm .+ mins
                cc = EPRCoordinate(M,mean(c,dims=2)...)
                try
                    o = get_orbit(M, cc.energy,cc.pitch,cc.r,cc.z, nstep=nstep,tmax=tmax)
                    if dl > 0.0
                        rpath = down_sample(o.path,mean_dl=dl)
                        o = Orbit(o.coordinate,o.class,o.tau_p,o.tau_t,rpath)
                    end
                    push!(orbs,o)
                    orbit_num = orbit_num + 1
                catch
                    o = Orbit(cc)
                    push!(orbs,o)
                    orbit_num = orbit_num + 1
                end
            else
                o = combine_orbits(orbits[inds_oc])
                push!(orbs,o)
                orbit_num = orbit_num + 1
            end
            orbit_index[orbs_index[inds_oc]] .= orbit_num
            nclusters = nclusters + nk
            continue
        end

        k = kmeans(coords,nk)
        if !combine
            coords = k.centers.*norm .+ mins
            for i=1:size(coords,2)
                w = k.assignments .== i
                sum(w) == 0 && continue
                cc = EPRCoordinate(M,coords[1,i],coords[2,i],coords[3,i])
                try
                    o = get_orbit(M, cc.energy, cc.pitch, cc.r, cc.z, nstep=nstep,tmax=tmax)
                    if dl > 0.0
                        rpath = down_sample(o.path,mean_dl=dl)
                        o = Orbit(o.coordinate,o.class,o.tau_p,o.tau_t,rpath)
                    end
                    push!(orbs,o)
                    orbit_num = orbit_num + 1
                catch
                    o = Orbit(cc)
                    push!(orbs,o)
                    orbit_num = orbit_num + 1
                end
                orbit_index[orbs_index[inds_oc[w]]] .= orbit_num
            end
        else
            for i=1:nk
                w = k.assignments .== i
                sum(w) == 0 && continue
                o = combine_orbits(orbits[inds_oc[w]])
                push!(orbs,o)
                orbit_num = orbit_num + 1
                orbit_index[orbs_index[inds_oc[w]]] .= orbit_num
            end
        end
        nclusters = nclusters + nk
    end

    counts = [count(x -> x == i, orbit_index) for i=1:length(orbs)]
    return orbs, OrbitGrid(eo,po,ro,counts,orbit_index,orbit_grid.class,orbit_grid.tau_p,orbit_grid.tau_t)

end

function Base.map(grid::OrbitGrid, f::Vector)
    if length(grid.counts) != length(f)
        throw(ArgumentError("Incompatible sizes"))
    end
    return [i == 0 ? zero(f[1]) : f[i]/grid.counts[i] for i in grid.index]
end

function combine_orbits(orbits)
    norbits = length(orbits)
    norbits == 1 && return orbits[1]

    o = orbits[1]
    r = o.path.r
    z = o.path.z
    phi = o.path.phi
    pitch = o.path.pitch
    energy = o.path.energy
    dt = o.path.dt
    dl = o.path.dl

    c = o.coordinate
    isa(c, EPRCoordinate) || error("Wrong orbit coordinate. Expected EPRCoordinate")
    ec = c.energy
    pc = c.pitch
    rc = c.r
    zc = c.z
    tau_p = o.tau_p
    tau_t = o.tau_t

    for i=2:norbits
        oo = orbits[i]
        ec = ec + oo.coordinate.energy
        pc = pc + oo.coordinate.pitch
        rc = rc + oo.coordinate.r
        zc = zc + oo.coordinate.z
        tau_t = tau_t + oo.tau_t
        tau_p = tau_p + oo.tau_p
        append!(r, oo.path.r)
        append!(z, oo.path.z)
        append!(phi, oo.path.phi)
        append!(pitch, oo.path.pitch)
        append!(energy, oo.path.energy)
        append!(dt, oo.path.dt)
        append!(dl, oo.path.dl)
    end
    ec = ec/norbits
    pc = pc/norbits
    rc = rc/norbits
    zc = zc/norbits
    tau_p = tau_p/norbits
    tau_t = tau_p/norbits

    cc = EPRCoordinate(ec,pc,rc,zc,c.amu,c.q)
    path = OrbitPath(r,z,phi,pitch,energy,dt,dl)

    if all(x -> x.class == orbits[1].class, orbits)
        class = orbits[1].class
    else
        class = :meta
    end

    return Orbit(cc, class, tau_p, tau_t, path)
end

function mc2orbit(M::AxisymmetricEquilibrium, d::FIDASIMGuidingCenterParticles; tmax=1200.0,nstep=12000)
    orbits = @distributed (vcat) for i=1:d.npart
        o = get_orbit(M,d.energy[i],M.sigma*d.pitch[i],d.r[i]/100,d.z[i]/100,tmax=tmax,nstep=nstep)
        o.coordinate
    end
    return orbits
end

function fbm2orbit(M::AxisymmetricEquilibrium,d::FIDASIMGuidingCenterFunction; n=1_000_000)
    dmc = fbm2mc(d,n=n)
    return mc2orbit(M,dmc)
end


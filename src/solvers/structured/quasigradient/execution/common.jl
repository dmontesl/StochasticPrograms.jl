function timestamp(quasigradient::AbstractQuasiGradient, ::AbstractQuasiGradientExecution)
    return quasigradient.data.iterations
end

function current_decision(quasigradient::AbstractQuasiGradient, ::AbstractQuasiGradientExecution)
    return quasigradient.x
end

function start_workers!(::AbstractQuasiGradient, ::AbstractQuasiGradientExecution)
    return nothing
end

function close_workers!(::AbstractQuasiGradient, ::AbstractQuasiGradientExecution)
    return nothing
end

function subobjectives(quasigradient::AbstractQuasiGradient, execution::AbstractQuasiGradientExecution)
    return execution.subobjectives
end

function set_subobjectives(quasigradient::AbstractQuasiGradient, Qs::AbstractVector, execution::AbstractQuasiGradientExecution)
    execution.subobjectives .= Qs
    return nothing
end

function solve_master!(quasigradient::AbstractQuasiGradient, ::AbstractQuasiGradientExecution)
    try
        MOI.optimize!(quasigradient.master)
    catch err
        status = MOI.get(quasigradient.master, MOI.TerminationStatus())
        # Master problem could not be solved for some reason.
        @unpack Q,θ = quasigradient.data
        gap = abs(θ-Q)/(abs(Q)+1e-10)
        # Always print this warning
        @warn "Master problem could not be solved, solver returned status $status. The following relative tolerance was reached: $(@sprintf("%.1e",gap)). Aborting procedure."
        rethrow(err)
    end
    return MOI.get(quasigradient.master, MOI.TerminationStatus())
end

function iterate!(quasigradient::AbstractQuasiGradient, ::AbstractQuasiGradientExecution)
    # Resolve all subproblems at the current optimal solution
    Q = resolve_subproblems!(quasigradient)
    if Q == Inf
        # Early termination log
        log!(quasigradient; status = MOI.INFEASIBLE)
        return MOI.INFEASIBLE
    end
    if Q == -Inf
        # Early termination log
        log!(quasigradient; status = MOI.DUAL_INFEASIBLE)
        return MOI.DUAL_INFEASIBLE
    end
    if Q <= quasigradient.data.Q
        quasigradient.data.Q = Q
    end
    # Determine stepsize
    γ = step(quasigradient,
             quasigradient.data.iterations,
             Q,
             quasigradient.subgradient)
    # Proximal subgradient update
    prox!(quasigradient,
          quasigradient.x,
          quasigradient.subgradient,
          γ)
    # Log progress
    log!(quasigradient)
    # Check optimality
    if terminate(quasigradient)
        # Optimal, final log
        log!(quasigradient; optimal = true)
        return MOI.OPTIMAL
    end
    # Dont return a status as procedure should continue
    return nothing
end

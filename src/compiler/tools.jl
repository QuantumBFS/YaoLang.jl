export gate_count

function gate_count(spec)
    ci, _ = code_yao(Semantic.main, spec; optimize=true)
    return gate_count(ci)
end

function gate_count(ci::CodeInfo)
    count = Dict{Symbol, Any}()
    for stmt in ci.code
        is_quantum_statement(stmt) || continue
        qt = quantum_stmt_type(stmt)

        if qt === :gate || qt === :ctrl
            gc = get!(count, qt, Dict{Symbol, Int}())
            if stmt.head === :invoke
                _, gt = obtain_gate_stmt(stmt.args[3], ci)
            elseif stmt.head === :call
                _, gt = obtain_gate_stmt(stmt.args[2], ci)
            end
            gc[routine_name(gt)] = get(gc, routine_name(gt), 0) + 1
        else
            count[qt] = get(count, qt, 0) + 1
        end
    end
    return count
end

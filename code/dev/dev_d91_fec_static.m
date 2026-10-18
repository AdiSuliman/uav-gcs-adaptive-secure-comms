function dev_d91_fec_static()
%DEV_D91_FEC_STATIC  Proof (a) of docs/d91_speed.md, no simulation: for the 36 configurations
%   in every threat cell of the pool stages (decision_config.m: the clean link, every single
%   threat at its five levels, every combination at C.combo_sev; build_check_pools.m and the
%   survivability maps fly levels of dataset_levels.m, also checked) at 2, 3 and 4 antennas,
%   each fec_interleave configuration's params less p.fec equal (isequal and the same key,
%   jsonencode) those of the configuration without it, at the same Eb/N0 offset, and the run
%   it takes is that configuration's (pool_configs.m). Also the runs per stage before and
%   after, weighted by pool_cost.m's emitter cost. Prints 'D91PROOF A_static PASS' or errors.
p0 = load('params.mat').params;
C = decision_config(); A = policy_actions(); nA = numel(A);
ifec = find(contains(A, 'fec_interleave'));
twin_of = @(a) regexprep(a, '\+?fec_interleave$', '');
sg = fieldnames(C.sev)';
DL = dataset_levels();
nchk = 0; bad = {};
for n = [2 3 4]
    p0.n_rx = n;
    cl = {}; sv = {};
    cl{end+1} = 'none'; sv{end+1} = p0;                                     %#ok<AGROW>
    for t = sg
        for v = 1:numel(C.sev_names), cl{end+1} = t{1}; sv{end+1} = threat_params(p0, t{1}, v, C); end %#ok<AGROW>
    end
    for t = C.combos
        for v = C.combo_sev, cl{end+1} = t{1}; sv{end+1} = threat_params(p0, t{1}, v, C); end %#ok<AGROW>
    end
    for d = DL
        for L = d.levels
            q = p0; q.active_threat = d.name; q.(d.param) = L; cl{end+1} = d.name; sv{end+1} = q; %#ok<AGROW>
        end
    end
    sv{1}.active_threat = 'none';
    old = 0; new = 0; wo = 0; wn = 0;
    for i = 1:numel(cl)
        [Cf, map, twin] = pool_configs(sv{i}, cl{i}, A);
        for a = ifec
            b = find(strcmp(A, twin_of(A{a}))); if isempty(b), b = find(strcmp(A, 'no_action')); end
            q = rmfield(Cf(a).p, 'fec');
            ok = isequal(q, Cf(b).p) && strcmp(jsonencode(q), jsonencode(Cf(b).p)) && Cf(a).g_db == Cf(b).g_db ...
                && twin(map(a)) == map(b) && Cf(a).p.fec;
            nchk = nchk + 1;
            if ~ok, bad{end+1} = sprintf('%d antennas, %s, %s', n, cl{i}, A{a}); end %#ok<AGROW>
        end
        nu = sum(map == 1:nA); nr = sum(twin == 1:nA);
        e = pool_cost(sv{i}, cl{i}, A, 20, []) / max(nr, 1);           % cost of one run of this cell
        if i <= 1 + numel(sg) * numel(C.sev_names) + numel(C.combos) * numel(C.combo_sev)
            old = old + nu; new = new + nr; wo = wo + nu * e; wn = wn + nr * e;
        end
    end
    fprintf(['%d antennas: %d cells checked; pool cells: %d runs -> %d (x%.3f), weighted by the emitter cost ' ...
        'x%.3f\n'], n, numel(cl), old, new, new / old, wn / wo);
end
fprintf('%d fec_interleave configurations checked, %d failed%s\n', nchk, numel(bad), sprintf('\n  %s', bad{:}));
if ~isempty(bad), fprintf('D91PROOF A_static FAIL\n'); error('dev_d91_fec_static:fail', 'proof (a) failed'); end
fprintf('D91PROOF A_static PASS\n');
end

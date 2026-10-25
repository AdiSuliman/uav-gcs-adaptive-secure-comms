function out = pool_job(stage, S, j)
%POOL_JOB  One job of a parallel pool stage, run by pool_lpt.m on a worker or on this process.
%   out = pool_job(stage, S, j): the body of the stage's loop over its jobs. S holds the
%   stage's variables the body reads, under the same names (or wrapped in a
%   parallel.pool.Constant); j is the job.
%   'c1p'   build_policy_pools.m:      j a cell; saves it (pool_checkpoint.m), out = []
%   'c1c'   build_check_pools.m:       j a cell; saves it, out = []
%   'clean' build_clean_test_pools.m:  j a chunk of geometries; saves it, out = []
%   'surv'  map_survivability_boundary.m:       j a job (threat entry, level); out {B, F, S},
%           configurations x Eb/N0 (x flights under surv_v2, S.NR set)
%   'surv3' experiment_survivability_options.m: j a job (case, option); out {rec, best}
if isa(S, 'parallel.pool.Constant'), S = S.Value; end
out = [];
switch stage
    case 'c1p'
        c = j; ce = S.cells(c);
        p = threat_params(S.p0, ce.threat, ce.sev, S.C);
        [Ps, pinfo] = pool_cell(p, ce.threat, S.ACTIONS, S.EBNO, S.geoc{c}, S.det, S.opt);
        Pc = cell(S.nS, S.nA, S.nSp);
        Pc(:, :, ce.splits) = Ps;
        pool_checkpoint('save', S.CKD, c, S.keys{c}, struct('Pc', {Pc}, 'nuniq', pinfo.n_unique));
        fprintf('  cell %2d/%d %-28s %-8s %2d unique configurations\n', c, S.nC, ce.threat, S.C.sev_names{ce.sev}, pinfo.n_unique);
    case 'c1c'
        c = j; ce = S.cells(c);
        p = S.p0; p.active_threat = ce.threat;
        if ~isempty(S.fld{c}), p.(S.fld{c}) = ce.level; end
        [Ps, pinfo] = pool_cell(p, ce.threat, S.ACTIONS, S.EB, S.geoc{c}, S.det, S.opt);
        pool_checkpoint('save', S.CKD, c, S.keys{c}, Ps);
        fprintf('  cell %2d/%d %-22s %-6s %6.2f  %2d unique configurations\n', c, S.nC, ce.threat, ce.kind, ce.level, pinfo.n_unique);
    case 'clean'
        pool_checkpoint('save', S.CKD, j, S.keys{j}, pool_cell(S.p0, 'none', S.ACTIONS, S.EBNO, S.geo(j, :), S.det, S.opt));
        fprintf('  geometries chunk %d/%d done\n', j, S.nJ);
    case 'surv'
        t = S.jobs(j, 1); li = S.jobs(j, 2);
        cfg = S.maps(t);
        p = S.p0; p.active_threat = cfg.base; p.(cfg.level_field) = cfg.levels(li);
        if isfield(cfg, 'pset'), for f = fieldnames(cfg.pset)', p.(f{1}) = cfg.pset.(f{1}); end, end   % the entry's own pattern (surv_nb_entries.m)
        if contains(cfg.base, 'airframe_shadowing'), [~, p.roll_deg] = shadow_roll_band(p.shadow_db, p); end   % a turn that lets the airframe hide an antenna
        p.gcs_aoa_deg = p.gcs_aoa_deg - rad2deg(9.81 * tand(p.roll_deg) / max(p.v_nominal, p.turn_v_floor)) * (S.RUN_FRAMES - 1) * p.cycle_s / 2;   % the turn carries the GCS through the beam at mid-run
        if ~isnan(cfg.aoa), p.int_aoa_deg(1) = p.gcs_aoa_deg + cfg.aoa; end
        if isempty(S.NR)
            sd = 900000 + 1000*t + 10*li;                         % + s: each Eb/N0 column its own flight (nS < 10)
            g = arrayfun(@(s) struct('seed', sd + s, 'speed', S.v_nom, 'run', 1), 1:S.nS, 'UniformOutput', false);
        else
            g = repmat({surv_flights(t, S.NR, S.v_nom)}, 1, S.nS);   % the entry's flights at every level and Eb/N0
        end
        P = pool_cell(p, cfg.base, S.ACTIONS, S.SNR_points, g, [], S.opt);
        if isempty(S.NR)
            rB = cellfun(@(Q) mean(Q.ber), P(:, :, 1))';            % configurations x Eb/N0
            rF = cellfun(@(Q) mean(double(Q.fer)), P(:, :, 1))';
            rS = cellfun(@(Q, a) packet_share(a, Q.fer), P(:, :, 1), repmat(S.ACTIONS(:)', S.nS, 1))';   % one loss event of the run
        else
            [rB, rF, rS] = surv_runs(P, S.ACTIONS, S.NR);            % configurations x Eb/N0 x flights
        end
        out = {rB, rF, rS};
    case 'surv3'
        c = S.cases(S.jobs(j, 1)); v = S.VAR(S.jobs(j, 2));
        p = S.p0; p.n_rx = v.n_rx; p.gcs_aoa_deg = v.gcs; p.link_loss_db = v.loss; p.active_threat = c.threat;
        if ~isempty(c.field), p.(c.field) = c.level; end
        P = pool_cell(p, c.threat, S.ACTIONS, S.EBNO, S.geo, [], S.opt);
        R = false(S.nS, S.N_GEOM); Bc = cell(S.nS, S.N_GEOM);
        for s = 1:S.nS
            bc = max(S.clean{v.ref}.ber(s), S.C.ber_floor); fc = S.clean{v.ref}.fer(s);
            for r = 1:S.N_GEOM
                rid = surv3_run_id(r); okc = false(1, numel(S.ACTIONS));
                for a = 1:numel(S.ACTIONS)
                    Q = P{s, a, 1}; m = Q.run == rid;
                    okc(a) = mean(Q.ber(m)) <= S.RATIO * bc && mean(double(Q.fer(m))) <= S.RATIO * fc + packet_share(S.ACTIONS{a}, Q.fer(m));
                end
                R(s, r) = any(okc);
                if any(okc), Bc{s, r} = S.ACTIONS{find(okc, 1)}; end
            end
        end
        out = {R, Bc};
    otherwise
        error('pool_job:stage', 'unknown stage %s', stage);
end
end

function out = core_bw_job(stage, S, j)
%CORE_BW_JOB  One job of the bandwidth study's parallel stages (experiment_core_bw.m), run by
%   pool_lpt.m on a worker or on this process. S holds the stage's variables (or a
%   parallel.pool.Constant of them); j is the job.
%   'pools'  one cell (or one residual layer of a cell) under its configurations through
%            pool_cell.m on its splits' geometries; saved by pool_checkpoint.m
%   'dset'   the detector-only set D of one cell: every frame's spectrogram image
%            (spec_image.m, as pool_cell.m gives the detector) on the no_action link; saved
if isa(S, 'parallel.pool.Constant'), S = S.Value; end
out = [];
J = S.jobs(j);
switch stage
    case 'pools'
        g = cellfun(@(x) x(J.splits), S.geo, 'UniformOutput', false);
        [P, info] = pool_cell(S.P{j}, J.threat, J.actions, S.EBNO, g, S.det, S.opt);
        pool_checkpoint('save', S.CKD, j, S.keys{j}, struct('P', {P}, 'nuniq', info.n_unique));
        fprintf('  job %3d/%d %-14s %-10s %d unique configurations\n', j, numel(S.jobs), J.name, J.layer, info.n_unique);
    case 'dset'
        pool_checkpoint('save', S.CKD, j, S.keys{j}, dset_cell(S.P{j}, S.EBNO, S.geo{j}, S.opt, S.fs));
        fprintf('  set D job %3d/%d %s\n', j, numel(S.jobs), J.name);
    otherwise
        error('core_bw_job:stage', 'core_bw_job: unknown stage %s', stage);
end
end

function D = dset_cell(p, ebno, geo, opt, fs)
% The no_action frames of one cell's set-D flights as pool_cell.m runs them: images,
% Eb/N0 index, run id and frame position.
modelName = 'UAV_GCS_Threat_Link';
build_threat_model(p);
nv = thermal_nv(p);
X = {}; s_ = []; run = []; pos = [];
for s = 1:numel(ebno)
    set_link_snr(modelName, ebno(s) + 10*log10(p.bits_per_symbol) - 10*log10(p.sps), p);
    g = geo{s};
    for r = 1:numel(g.seed)
        fd = g.speed(r) / 3.6 * p.carrier_freq / p.c_light;
        link_seed(modelName, g.seed(r), fd, struct('ebno', ebno(s), 'alt_m', NaN, 'k_sig_db', NaN, 'aoa1_deg', NaN, ...
            'rho', NaN, 'event_frame', NaN, 'frames', opt.F_SUB));
        F = extract_closed_loop_frames(sim(modelName, 'StopTime', num2str((opt.F_SUB - 1) * p.frame_duration)), p, ...
            opt.delay_bits);
        disk_guard;
        v = find(~isnan(F.ber));
        Xr = zeros(128, 128, 1, numel(v), 'single');
        for i = 1:numel(v), Xr(:, :, 1, i) = spec_image(F.iq{v(i)}, fs, nv); end
        X{end+1} = Xr; %#ok<AGROW>
        s_ = [s_; s * ones(numel(v), 1)]; run = [run; g.run(r) * ones(numel(v), 1)]; pos = [pos; v(:)]; %#ok<AGROW>
    end
end
D = struct('X', cat(4, X{:}), 's', s_, 'run', run, 'pos', pos);
end

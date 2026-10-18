function dev_d91_profile(out_dir, src)
%DEV_D91_PROFILE  Where an emitter's simulation time goes (docs/d91_speed.md, step 5): one
%   configuration (no_action), one Eb/N0 (the middle of the grid), three flights of the train
%   block, as pool_cell.m flies them, on one core.
%   1. Stage times without a profiler, the clean link and jamming at the nominal level on the
%      same flights: model build, link_seed, sim, extract_closed_loop_frames (idle_rssi.m and
%      mmse_predict.m timed again on their own) and add_run's detector part (spec_image,
%      link_features, detect_scores).
%   2. Jamming again under the MATLAB profiler (functions by self time) and the Simulink
%      profiler (blocks by self time, summed into threat, channel, receiver, transmitter, sinks
%      and the rest).
%   Prints both and saves profile.mat in out_dir.
p0 = load('params.mat').params; p0.quiet_build = true;
C = decision_config();
det = dev_d91_det(src, p0);
mdl = 'UAV_GCS_Threat_Link';
opt = struct('F_SUB', 20, 'tw', 10, 'delay_bits', 20);
si = ceil(numel(p0.EbNo_dB) / 2); eb = p0.EbNo_dB(si);
g = pool_geometries(si, 1, 1:3, [p0.speed_kmh_min p0.speed_kmh_max], p0);
stop = num2str((opt.F_SUB - 1) * p0.frame_duration);
T = {'none', 'jamming'};
S = struct();
for i = 1:2
    [p2, g_db] = apply_countermeasure(threat_params(p0, T{i}, C.nominal, C), T{i}, 'no_action'); p2.seed = [];
    t0 = tic; evalc('build_threat_model(p2)'); tb = toc(t0);
    if ~isempty(det), det.nv = thermal_nv(p2); end
    set_link_snr(mdl, eb + 10*log10(p2.bits_per_symbol) - 10*log10(p2.sps) + g_db, p2);
    tt = zeros(numel(g.seed), 6);
    for r = 1:numel(g.seed)
        fd = g.speed(r) / 3.6 * p0.carrier_freq / p0.c_light;
        t0 = tic; link_seed(mdl, g.seed(r), fd, struct('ebno', eb, 'alt_m', g.alt(r), 'k_sig_db', g.ksig(r), ...
            'aoa1_deg', g.aoa1(r), 'rho', g.rho(r), 'frames', opt.F_SUB)); tt(r, 1) = toc(t0);
        t0 = tic; o = sim(mdl, 'StopTime', stop); tt(r, 2) = toc(t0);
        t0 = tic; F = extract_closed_loop_frames(o, p2, opt.delay_bits); tt(r, 3) = toc(t0);
        t0 = tic; try, idle_alone(o, p2, F.nf); tt(r, 4) = toc(t0); catch, tt(r, 4) = NaN; end
        t0 = tic; try, mmse_predict(o.get('Rx_IQ'), p2, reshape(o.get('Rx_S'), 8, [])); tt(r, 5) = toc(t0); catch, tt(r, 5) = NaN; end
        t0 = tic; detector_part(F, det, opt.tw); tt(r, 6) = toc(t0);
        disk_guard;
    end
    S.(T{i}) = struct('build_s', tb, 'per_run_s', tt);
    fprintf(['%-8s build %.1f s | per 20-frame run [s], mean of %d flights: link_seed %.3f | sim %.3f | extract %.3f ' ...
        '(of it idle_rssi %.3f, mmse_predict %.3f) | detector part %.3f\n'], T{i}, tb, numel(g.seed), mean(tt, 1));
end
d = mean(S.jamming.per_run_s, 1) - mean(S.none.per_run_s, 1);
fprintf('jamming - clean per run [s]: sim %+.3f | extract %+.3f (idle_rssi %+.3f, mmse_predict %+.3f) | detector %+.3f\n', d(2:6));

% 2. Profilers (jamming)
[p2, g_db] = apply_countermeasure(threat_params(p0, 'jamming', C.nominal, C), 'jamming', 'no_action'); p2.seed = [];
evalc('build_threat_model(p2)');
set_link_snr(mdl, eb + 10*log10(p2.bits_per_symbol) - 10*log10(p2.sps) + g_db, p2);
try
    set_param(mdl, 'Profile', 'on');
catch err
    fprintf('Simulink profiler not available: %s\n', err.message);
end
profile('clear'); profile('on');
blk = {};
for r = 1:numel(g.seed)
    fd = g.speed(r) / 3.6 * p0.carrier_freq / p0.c_light;
    link_seed(mdl, g.seed(r), fd, struct('ebno', eb, 'alt_m', g.alt(r), 'k_sig_db', g.ksig(r), ...
        'aoa1_deg', g.aoa1(r), 'rho', g.rho(r), 'frames', opt.F_SUB));
    o = sim(mdl, 'StopTime', stop);
    F = extract_closed_loop_frames(o, p2, opt.delay_bits);
    detector_part(F, det, opt.tw);
    blk = [blk; sl_profile_rows(o)]; %#ok<AGROW>
    disk_guard;
end
profile('off');
try, set_param(mdl, 'Profile', 'off'); catch, end
pi_ = profile('info');
ft = pi_.FunctionTable;
[~, k] = sort([ft.TotalTime] - arrayfun(@(f) sum([f.Children.TotalTime]), ft)', 'descend');
fprintf('\nMATLAB profiler, jamming, %d runs: functions by self time [s] (total, calls)\n', numel(g.seed));
for j = k(1:min(30, end))
    f = ft(j); st = f.TotalTime - sum([f.Children.TotalTime]);
    fprintf('  %8.3f  %8.3f  %6d  %s\n', st, f.TotalTime, f.NumCalls, f.FunctionName);
end
S.matlab = arrayfun(@(f) struct('name', f.FunctionName, 'total', f.TotalTime, 'self', f.TotalTime - sum([f.Children.TotalTime]), ...
    'calls', f.NumCalls), ft);
S.blocks = blk;
if isempty(blk)
    fprintf('\nSimulink profiler: no block data in the simulation output\n');
else
    [nm, ~, j] = unique(blk(:, 1));
    self = accumarray(j, cell2mat(blk(:, 2)));
    [self, o2] = sort(self, 'descend'); nm = nm(o2);
    fprintf('\nSimulink profiler, jamming, %d runs: blocks by self time [s]\n', numel(g.seed));
    for j = 1:min(25, numel(nm)), fprintf('  %8.3f  %s\n', self(j), nm{j}); end
    grp = {'tx_sink|rx_sink|Tx_IQ|Rx_IQ|Rx_Z|Rx_H|Rx_R|Rx_S|Thr_act|Thr_comp|Thr_sig|Cal_db', 'Threat', 'Channel', 'Rx', 'Tx', ...
        'AWGN', 'BitSource'};
    gl = {'sinks', 'threat', 'channel', 'receiver', 'transmitter', 'AWGN', 'bit source'};
    acc = zeros(1, numel(grp) + 1);
    for j = 1:numel(nm)
        leaf = regexprep(nm{j}, '^[^/]*/', '');
        h = find(cellfun(@(e) ~isempty(regexp(leaf, ['^(' e ')(/|$)'], 'once')), grp), 1);
        if isempty(h), h = numel(grp) + 1; end
        acc(h) = acc(h) + self(j);
    end
    gl = [gl, {'other'}];
    fprintf('  by part [s per run]: %s\n', strjoin(arrayfun(@(h) sprintf('%s %.3f', gl{h}, acc(h) / numel(g.seed)), ...
        1:numel(acc), 'UniformOutput', false), ' | '));
    S.block_parts = struct('names', {gl}, 'seconds_per_run', acc / numel(g.seed));
end
save(fullfile(out_dir, 'profile.mat'), 'S', '-v7.3');
close_system(mdl, 0);
end

function idle_alone(o, p, nf)
% The idle-time RSSI alone, as extract_closed_loop_frames.m calls it.
if ~isfield(p, 'idle_rssi_hz') || isempty(p.idle_rssi_hz) || p.idle_rssi_hz <= 0, return; end
ctx = idle_context(o.SimulationMetadata.ModelInfo.ModelName);
ion = [];
try
    c = o.get('Thr_comp');
    nc = size(c, 2); if ndims(c) == 3, nc = numel(c) / size(c, 3); end
    if ndims(c) == 3, c = reshape(c, nc, []); else, c = reshape(c, [], nc).'; end
    c = c(:, [1:min(nf, size(c, 2)), size(c, 2) * ones(1, nf - size(c, 2))]);
    if nc > 6, ion = permute(reshape(c(7:end, :), [], 3, nf), [2 1 3]); end
catch
end
if ~isempty(ctx), idle_rssi(p, ctx, ion, 1:nf); end
end

function detector_part(F, det, tw)
% add_run's detector part (pool_cell.m): images, features and one scoring call.
if isempty(det), return; end
v = find(~isnan(F.ber)); n = numel(v);
X = zeros(128, 128, 1, n, 'single'); Fr = zeros(n, numel(det.mu));
for i = 1:n
    X(:, :, 1, i) = spec_image(F.iq{v(i)}, det.fs, det.nv);
    Fr(i, :) = link_features(F, v(i), tw);
end
detect_scores(det.net, det.ood, X, ((Fr - det.mu) ./ det.sd)', 'cpu');
end

function rows = sl_profile_rows(o)
% Block self times of one run from the Simulink profiler: {block path, seconds}; empty when the
% output holds no profile.
rows = cell(0, 2);
pd = [];
try, pd = o.SimulinkProfileInfo; catch, end
if isempty(pd)
    try, pd = o.get('SimulinkProfileInfo'); catch, end
end
if isempty(pd), return; end
try
    rows = walk(pd.rootUINode, rows);
catch err
    fprintf('Simulink profile of class %s not read: %s\n', class(pd), err.message);
    try, disp(properties(pd)); catch, end
end
end

function rows = walk(n, rows)
% Depth-first over the profile's nodes.
for k = 1:numel(n)
    nm = ''; for f = {'objectPath', 'path', 'name', 'locationName'}
        if isprop(n(k), f{1}) || isfield(n(k), f{1}), nm = char(n(k).(f{1})); break; end
    end
    st = NaN; for f = {'selfTime', 'SelfTime'}
        if isprop(n(k), f{1}) || isfield(n(k), f{1}), st = double(n(k).(f{1})); break; end
    end
    rows(end+1, :) = {nm, st}; %#ok<AGROW>
    ch = [];
    for f = {'children', 'Children'}
        if isprop(n(k), f{1}) || isfield(n(k), f{1}), ch = n(k).(f{1}); break; end
    end
    if ~isempty(ch), rows = walk(ch, rows); end
end
end

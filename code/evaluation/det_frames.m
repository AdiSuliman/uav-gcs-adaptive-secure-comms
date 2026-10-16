function [hit, on, hit_f, age] = det_frames(P, Pc, scen, ok_c, PP, runs, ev)
%DET_FRAMES  DET of every frame of a pool at no_action (edge_map.m): hit (frames x rows of
%   ok_c, the classes edge_map.m counts for the threat and for its branch level), the
%   monitor's class is one ok_c counts for the threat; on, the threat is on the air
%   (threat_active.m, per decision cycle: in the frame or the idle time before it). The
%   monitor's class (policy_monitor.m) is the fused class, and while the latched cause of a
%   lost branch holds (onset_shape.m: read from the shape of its onset) that cause for a
%   fused antenna_fault or airframe_shadowing; hit_f the same
%   reading by the fused class alone. A path-loss or antenna-fault cell, alone or in a
%   combination, has its full loss from its run's first frame, so every flight is read after
%   the same flight's clean link (Pc, the onset between them: the connector's step, the
%   loss's step), the fused class over the joined frames. A flight that rolls into its turn
%   (runs, ev: the split's geometry ids and the frame at which the airframe enters the line
%   of sight on each, PP.event_frame; NaN none) is read as its episodes read it (link_env.m):
%   the same flight's clean link on its frames before that one as the lead-in, the cell's
%   frames from it on; the cell's earlier frames are never read (on false, age NaN). With
%   the monitor's drop alarm ('class_drop', 'class_cusum') the class path_loss counts only
%   with the drop, so the path-loss component is detected by the drop alarm alone, against
%   the median of the last 10 clean cycles of the lead-in: 'class_drop' the Eb/N0
%   estimate's 3-cycle median that many dB below it, 'class_cusum' the window-limited CUSUM
%   of every cycle's drop below it reaching the threshold (drop_cusum.m, policy_monitor.m).
%   age: cycles of every frame since its run's first frame read with the threat on the air
%   (NaN before it): the fusion window holds the onset while age < PP.fuse_N.
ai = []; if isfield(P, 'act_idle'), ai = P.act_idle; end
on = reshape(threat_active(scen, P.act, [], [], ai), [], 1);
mode = ''; if isfield(PP, 'alarm_mode'), mode = PP.alarm_mode; end
use_drop = any(strcmp(mode, {'class_drop', 'class_cusum'}));
parts = strsplit(scen, '+');
has_pl = any(strcmp(parts, 'path_loss'));
if use_drop && has_pl, ok_c(:, strcmp(cellstr(string(PP.classes)), 'path_loss')) = false; end
has_c = ~isempty(Pc) && ~isempty(Pc.ber);
join = (has_pl || any(strcmp(parts, 'antenna_fault'))) && has_c;
if nargin < 7, runs = []; ev = []; end
C = decision_config();
[ur, ~, ir] = unique(P.run, 'stable');
J = struct('probs', [], 'gant', [], 'feat', [], 'run', [], 'part', [], 'idle', [], 'bch', []);
Ip = idle_of(P); Ic = zeros(0, size(Ip, 2));
if has_c, Ic = idle_of(Pc); end
Bp = bch_of(P); Bc = zeros(0, size(Bp, 2));
if has_c, Bc = bch_of(Pc); end
for r = 1:numel(ur)
    ip = find(ir == r); ic = zeros(0, 1);
    e0 = NaN; k = find(runs == ur(r), 1); if ~isempty(k), e0 = ev(k); end
    if isfinite(e0)                                      % a rolling-in flight: from its event's frame on
        on(ip(1:min(e0 - 1, end))) = false;
        ip = ip(min(e0, numel(ip) + 1):end);
        if has_c, ic = find(Pc.run == ur(r)); ic = ic(1:min(e0 - 1, end)); end
    elseif join
        ic = find(Pc.run == ur(r));
    end
    J.probs = [J.probs; Pc_rows(Pc, 'probs', ic); P.probs(ip, :)]; J.gant = [J.gant; Pc_rows(Pc, 'gant', ic); P.gant(ip, :)];
    J.feat = [J.feat; Pc_rows(Pc, 'feat', ic); P.feat(ip, :)]; J.run = [J.run; repmat(ur(r), numel(ic) + numel(ip), 1)];
    J.part = [J.part; zeros(numel(ic), 1); ip(:)];
    J.idle = [J.idle; Ic(ic, :); Ip(ip, :)];
    if ~isempty(Bp), J.bch = [J.bch; Bc(ic, :); Bp(ip, :)]; end
end
pc = double(J.probs);
if ~isempty(PP.fuse)
    S = struct('run', J.run, 'pos', run_pos(J.run), 'gain_ant', J.gant, 'feats_raw', J.feat, 'feat_names', ...
        {link_features('names')}, 'idle', J.idle, 'bch', J.bch);
    pc = fuse_classes('apply', PP.fuse, fuse_classes('windows', S, pc, PP.fuse_N));
end
[~, k] = max(pc, [], 2);
kl = k;                                                  % with the latched cause of a lost branch
if ~isempty(J.gant)
    for r = 1:numel(ur)
        j = find(J.run == ur(r));
        [~, kl(j)] = max(onset_shape('sequence', J.gant(j, :), pc(j, :), PP.classes, C.heal, ...
            onset_shape('threshold', PP.fuse)), [], 2);
    end
end
dd = C.drop_db; if isfield(PP, 'drop_db') && ~isempty(PP.drop_db), dd = PP.drop_db; end
eb = @(F) double(F(:, feature_index('sinr')) + F(:, feature_index('iot'))) + 10*log10(PP.sps) - 10*log10(PP.bps);
e = eb(J.feat);
hit = false(numel(P.run), size(ok_c, 1)); hit_f = hit; age = nan(numel(P.run), 1);
for r = 1:numel(ur)
    j = find(J.run == ur(r)); jc = j(J.part(j) == 0); jp = j(J.part(j) > 0);
    hit(J.part(jp), :) = ok_c(:, kl(jp))';
    hit_f(J.part(jp), :) = ok_c(:, k(jp))';
    ip = J.part(jp); f0 = find(on(ip), 1);
    if ~isempty(f0), age(ip(f0:end)) = (0:numel(ip) - f0)'; end
    if ~use_drop || ~has_pl || isempty(jc), continue; end
    ref = median(e(jc(max(1, end - 9):end)));
    if strcmp(mode, 'class_cusum')                       % its window from the lead-in's last cycles
        dr = seq_cusum(ref - e(jp), ref - e(jc), C.cusum_win) >= dd;
    else
        dr = arrayfun(@(q) ref - median(e(max(j(1), q - 2):q)) >= dd, jp(:)');
    end
    hit(ip, :) = hit(ip, :) | dr(:);
    hit_f(ip, :) = hit_f(ip, :) | dr(:);
end
end

function W = seq_cusum(d, dl, w)
% drop_cusum.m over the drops d of the read cycles, its window filled by the lead-in's last
% w drops dl, the statistic from 0 at the first read cycle.
d = d(:)'; dl = dl(:)';
dx = [nan(1, w - min(numel(dl), w)), dl(max(1, end - w + 1):end)];
W = zeros(size(d)); w0 = 0;
for t = 1:numel(d)
    w0 = drop_cusum(d(t), w0, dx); W(t) = w0;
    dx = [dx(2:end), d(t)];
end
end

function X = Pc_rows(Pc, f, ic)
% Rows ic of field f of the clean link's pool (none without a lead-in).
if isempty(ic), X = zeros(0, 0); else, X = Pc.(f)(ic, :); end
end

function pos = run_pos(run)
% Position of every frame in its run (the frames of a run are consecutive).
st = [true; diff(run(:)) ~= 0];
i0 = find(st);
pos = (1:numel(run))' - i0(cumsum(st)) + 1;
end

function B = bch_of(P)
% The antennas' channel records of a pool (branch_record.m), empty for pools without them.
B = [];
if isfield(P, 'bch') && ~isempty(P.bch), B = double(P.bch); end
end

function I = idle_of(P)
% The idle-time records of a pool (idle_summary.m), NaN for pools without them.
if isfield(P, 'idle') && ~isempty(P.idle)
    I = double(P.idle);
else
    I = nan(numel(P.run), numel(idle_summary('names')));
end
end

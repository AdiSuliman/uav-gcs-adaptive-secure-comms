function [hit, on] = det_frames(P, Pc, scen, ok_c, PP)
%DET_FRAMES  DET of every frame of a pool at no_action (edge_map.m): hit (frames x rows of
%   ok_c, the classes edge_map.m counts for the threat and for its branch level), the
%   fused class is one ok_c counts for the threat; on, the threat is on the air
%   (threat_active.m, per decision cycle: in the frame or the idle time before it). A
%   path-loss cell, alone or in a combination, starts with its full
%   loss, so every flight is read after the same flight's clean link (Pc, the onset between
%   them): the fused class over the joined frames, and with the monitor's 'class_drop'
%   alarm the class path_loss counts only with the drop, so the path-loss component is
%   detected by the drop alarm alone: the Eb/N0 estimate's 3-cycle median that many dB
%   below the median of the last 10 clean cycles (policy_monitor.m).
ai = []; if isfield(P, 'act_idle'), ai = P.act_idle; end
on = reshape(threat_active(scen, P.act, [], [], ai), [], 1);
use_drop = isfield(PP, 'alarm_mode') && strcmp(PP.alarm_mode, 'class_drop');
has_pl = any(strcmp(strsplit(scen, '+'), 'path_loss'));
if use_drop && has_pl, ok_c(:, strcmp(cellstr(string(PP.classes)), 'path_loss')) = false; end
if ~has_pl || isempty(Pc) || isempty(Pc.ber)
    k = fused_class(P.probs, struct('run', P.run, 'pos', run_pos(P.run), 'gain_ant', P.gant, 'feats_raw', P.feat, ...
        'idle', idle_of(P)), PP.fuse, PP.fuse_N);
    hit = ok_c(:, k(:))';
    return
end
C = decision_config();
dd = C.drop_db; if isfield(PP, 'drop_db') && ~isempty(PP.drop_db), dd = PP.drop_db; end
eb = @(F) double(F(:, feature_index('sinr')) + F(:, feature_index('iot'))) + 10*log10(PP.sps) - 10*log10(PP.bps);
hit = false(numel(P.run), size(ok_c, 1));
[ur, ~, ir] = unique(P.run, 'stable');
J = struct('probs', [], 'gant', [], 'feat', [], 'run', [], 'part', [], 'idle', []);
Ip = idle_of(P); Ic = idle_of(Pc);
for r = 1:numel(ur)
    ic = find(Pc.run == ur(r)); ip = find(ir == r);
    J.probs = [J.probs; Pc.probs(ic, :); P.probs(ip, :)]; J.gant = [J.gant; Pc.gant(ic, :); P.gant(ip, :)];
    J.feat = [J.feat; Pc.feat(ic, :); P.feat(ip, :)]; J.run = [J.run; repmat(ur(r), numel(ic) + numel(ip), 1)];
    J.part = [J.part; zeros(numel(ic), 1); ip(:)];
    J.idle = [J.idle; Ic(ic, :); Ip(ip, :)];
end
k = fused_class(J.probs, struct('run', J.run, 'pos', run_pos(J.run), 'gain_ant', J.gant, 'feats_raw', J.feat, ...
    'idle', J.idle), PP.fuse, PP.fuse_N);
e = eb(J.feat);
for r = 1:numel(ur)
    j = find(J.run == ur(r)); jc = j(J.part(j) == 0); jp = j(J.part(j) > 0);
    hit(J.part(jp), :) = ok_c(:, k(jp))';
    if ~use_drop || isempty(jc), continue; end
    ref = median(e(jc(max(1, end - 9):end)));
    for q = jp(:)'
        hit(J.part(q), :) = hit(J.part(q), :) | ref - median(e(max(j(1), q - 2):q)) >= dd;
    end
end
end

function pos = run_pos(run)
% Position of every frame in its run (the frames of a run are consecutive).
st = [true; diff(run(:)) ~= 0];
i0 = find(st);
pos = (1:numel(run))' - i0(cumsum(st)) + 1;
end

function I = idle_of(P)
% The idle-time records of a pool (idle_summary.m), NaN for pools without them.
if isfield(P, 'idle') && ~isempty(P.idle)
    I = double(P.idle);
else
    I = nan(numel(P.run), numel(idle_summary('names')));
end
end

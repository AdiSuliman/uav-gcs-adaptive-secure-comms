function [R, meta] = v3d_replay(src, M)
%V3D_REPLAY  Cycle records of an episode recorded by the operator console.
%   [R, meta] = v3d_replay(file, M)    file: GUI_Results/episode_*.mat (struct ep3d)
%
%   The console's continuous episode runs the full Simulink link every cycle, at
%   any severity and speed. Its trace (per policy: detected class and confidence,
%   configuration, switches, frame BER, Q-values) becomes records in the format of
%   v3d_engine.m, so the 3D view plays it like a live session. The record keeps
%   only the top class, so the detector panel shows that class alone; the alarm is
%   counted as confirmed when the class is hostile in two consecutive frames, and
%   the link state comes from the frame BER (mean of the last 3 frames) against
%   the clean-link BER of the episode.
if isstruct(src), ep = src; else, L = load(src, 'ep3d'); ep = L.ep3d; end
T = ep.T;
iD = find(strcmp(ep.policies, 'dqn'), 1); if isempty(iD), iD = 1; end
iB = setdiff(1:numel(ep.policies), iD); if isempty(iB), iB = iD; else, iB = iB(1); end
rows = [iD iB];
comps = strsplit(ep.threat, '+');
emit = comps(ismember(comps, M.emitters));
th = zeros(1, numel(emit)); inr = th;
for j = 1:numel(emit)
    th(j) = ep.int_aoa_deg(min(j, numel(ep.int_aoa_deg)));
    switch emit{j}
        case 'spoofing',            inr(j) = ep.ebno - ep.sev.spoof_sir_db;
        case 'benign_interference', inr(j) = ep.ebno + ep.sev.benign_int_db;
        otherwise,                  inr(j) = ep.ebno + ep.sev.jsr_db;
    end
end
bc = max(ep.ber_clean, decision_config().ber_floor);
G = struct('onsetT', ep.n_pre + 1, 'events0', {{}});
G.hist = struct('chan', {3, 3}, 'hops', {0, 0}, 'comp', {false, false});
G.sides = struct('phase', {'clean', 'clean'}, 'okRun', {0, 0}, 'wasOk', {true, true}, 'detT', {0, 0}, ...
    'confT', {0, 0}, 'actT', {0, 0}, 'recT', {0, 0});
G.score = repmat(struct('n', 0, 'restored', 0, 'reward', 0, 'switches', 0, 'false_sw', 0, 't_rec', NaN), 1, 2);
R = cell(1, ep.n);
for k = 1:ep.n
    rec = struct('t', k, 'scn', M.avail(find(strcmp(M.PP.scen(M.avail), ep.threat), 1)), 'threat', ep.threat, 'active', k > ep.n_pre, ...
        's', NaN, 'ebno', ep.ebno, 'r', NaN, 'follow', false, 'unk', any(T.unk(:, k)), ...
        'emit', {{}}, 'th', [], 'inr', [], 'speed', ep.v_kmh);
    if rec.active, rec.emit = emit; rec.th = th; rec.inr = inr; end
    side = struct([]);
    for s = 1:2
        i = rows(s);
        sd = struct();
        sd.cfg = T.cfg(i, k); sd.act = ep.actions{sd.cfg};
        sd.switched = logical(T.sw(i, k)); sd.escalated = false;
        p = zeros(1, 9); p(T.det(i, k)) = T.conf(i, k);
        sd.probs = p; sd.unknown = logical(T.unk(i, k));
        sd.conf = T.conf(i, k); sd.cls = ep.classes{T.det(i, k)}; sd.monitor = sd.cls;
        hostile = T.det(i, k) ~= 1 && k > 1 && T.det(i, k - 1) ~= 1;
        sd.confirmed = rec.active && hostile;
        b = mean(T.ber(i, max(1, k - 2):k));
        sd.degraded = b / bc > 2;
        q = squeeze(T.q(i, k, :))';
        if s == 1 && any(isfinite(q) & q ~= 0), sd.q = q; else, sd.q = []; end
        sd.ber = b; sd.ratio = b / bc;
        sd.restored = sd.ratio <= 2;
        if sd.restored, sd.status = 'ok'; elseif sd.ratio <= 5, sd.status = 'marginal'; else, sd.status = 'lost'; end
        sd.reward = 0; sd.q_link = NaN; sd.gput = NaN;
        sd.false_sw = sd.switched && ~rec.active;
        sd.compromised = false;
        if k > 1, sd.prev = T.cfg(i, k - 1); else, sd.prev = M.na; end
        [G, sd] = v3d_engine('annotate', G, M, s, sd, rec);
        sd = rmfield(sd, 'prev');
        side = [side, sd]; %#ok<AGROW>
    end
    rec.side = side;
    rec.events = {};
    if k == ep.n_pre + 1, rec.events = {sprintf('%s switched on', strrep(ep.threat, '_', ' '))}; end
    R{k} = rec;
end
R = [R{:}];
names = containers.Map({'dqn', 'rule', 'none', 'fixed'}, {'DQN', 'Rules', 'No response', 'Fixed'});
if isKey(names, ep.policies{iB}), right = names(ep.policies{iB}); else, right = ep.policies{iB}; end
meta = struct('title', 'Recorded episode (operator console)', ...
    'subtitle', sprintf('%s  |  Eb/N0 %g dB  |  severity %s  |  %.0f km/h  |  full Simulink link', ...
    strrep(ep.threat, '_', ' '), ep.ebno, ep.sev_txt, ep.v_kmh), 'right', right, 'frame_s', ep.frame_s, ...
    'T', ep.n, 'footer', ['Not to scale: positions illustrative, directions from the link model  |  recorded ' ...
    'console episode (Simulink link every cycle)  |  HIT capstone 50076']);
end

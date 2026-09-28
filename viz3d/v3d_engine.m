function varargout = v3d_engine(cmd, varargin)
%V3D_ENGINE  Closed-loop episode engine of the 3D view (D57).
%   The evaluation's decision layer on the measured TEST pools (link_env.m,
%   policy_decide.m, the selected DQN agent, the same link monitor and shield),
%   two policies on the same flight geometry and the same frames, with live
%   threat control. Side 1 is always the DQN agent; side 2 is the comparison.
%
%   M = v3d_engine('load')                        pools, agent, tables, names (once)
%   G = v3d_engine('new', M, opt)                 new episode, clean link
%        opt: s (Eb/N0 index), r (test geometry 1..4), right ('rule' | 'none' |
%        'operator'), seed
%   G = v3d_engine('inject', G, M, scn, follow, unk)   threat from the next cycle
%   G = v3d_engine('clear', G)                    threat off from the next cycle
%   G = v3d_engine('operator', G, a)              operator's configuration (side 2)
%   [G, rec] = v3d_engine('step', G, M)           one decision cycle for both sides
%   R = v3d_engine('script', M, sc)               a whole scripted episode (records)
%   [G, sd] = v3d_engine('annotate', G, M, i, sd, rec)   channels, phase, events and
%        score of side i for a record built elsewhere (v3d_replay.m)
%
%   rec (one cycle): t, scn, threat, active, s, ebno, r, emit (emitter names),
%   th (their broadside angles), inr, follow, unk, and per side (1 x 2 struct
%   array 'side'): cfg, act (name), switched, escalated, cls, conf, probs, unknown,
%   confirmed, degraded, q (Q-values, side 1), ratio (BER of the configuration in
%   use / clean BER), ber, status ('ok' | 'marginal' | 'lost'), restored, reward,
%   false_sw, compromised, chan, chan2, chan_jam, phase, events (cellstr), score.
switch cmd
    case 'load',     varargout{1} = loadAll();
    case 'new',      varargout{1} = newEpisode(varargin{:});
    case 'inject',   varargout{1} = inject(varargin{:});
    case 'clear',    varargout{1} = clearThreat(varargin{:});
    case 'operator', G = varargin{1}; G.opcfg = varargin{2}; varargout{1} = G;
    case 'step',     [varargout{1}, varargout{2}] = step(varargin{:});
    case 'script',   varargout{1} = script(varargin{:});
    case 'annotate', [varargout{1}, varargout{2}] = annotate(varargin{:});
    otherwise, error('v3d_engine: unknown command %s', cmd);
end
end

%% ===================== Load =====================
function M = loadAll()
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
L = load(fullfile(root, 'data', 'policy_pools.mat'), 'PP'); PP = L.PP;
Q = load(fullfile(root, 'data', 'trained_dqn.mat'), 'agents', 'gammas', 'seed_summary', 'confirm', 'alarm_mode', 'drop_db');
PP.confirm = Q.confirm; PP.alarm_mode = Q.alarm_mode;
if isfield(Q, 'drop_db') && ~isempty(Q.drop_db), PP.drop_db = Q.drop_db; end
M.PP = PP;
M.K = link_env('tables', PP);
M.agent = Q.agents{find(Q.gammas == Q.seed_summary.selected_gamma, 1)};
M.na = M.K.na;
M.split = 2;
M.nR = numel(PP.runs{2});
M.avail = find(cellfun(@(p) ~isempty(p) && ~isempty(p.ber), PP.pools(:, 1, M.na, 2)))';
S = load(fullfile(root, 'params.mat')); p = S.params;
M.sev = struct('jsr_db', p.jsr_db, 'spoof_sir_db', p.spoof_sir_db, 'benign_db', p.benign_int_db, ...
    'path_loss_db', p.path_loss_db, 'fault_duty', p.fault_duty);
M.frame_s = p.frame_duration;
M.emitters = {'jamming', 'reactive_jamming', 'sweeping_jammer', 'noise_burst', 'spoofing', 'benign_interference'};
M.inChannel = {'jamming', 'reactive_jamming', 'spoofing'};
M.hopSeq = [6 1 8 4 7 2 5 3];
end

%% ===================== Episode control =====================
function G = newEpisode(M, opt)
if ~isfield(opt, 'seed'), opt.seed = 1; end
if ~isfield(opt, 'right'), opt.right = 'rule'; end
G.s = opt.s; G.r = opt.r; G.right = opt.right; G.opcfg = M.na;
spec = struct('scn', [1 1], 's', [opt.s opt.s], 'onset', [inf inf], 'follow', [false false], ...
    'fdelay', [3 3], 'unk', [false false], 'T', inf, 'r', [opt.r opt.r]);
[G.E, G.obs] = link_env('reset', M.PP, M.K, spec, M.split, RandStream('mt19937ar', 'Seed', opt.seed));
G.E.k0(2) = G.E.k0(1);                             % both sides read the same frames
G.obs = sliceObs(G.obs, [1 1]);
G.mem = {[], []};
G.scn = 1; G.pending = [];
G.hist = struct('chan', {3, 3}, 'hops', {0, 0}, 'comp', {false, false});
G.sides = struct('phase', {'clean', 'clean'}, 'okRun', {0, 0}, 'wasOk', {true, true}, 'detT', {0, 0}, ...
    'confT', {0, 0}, 'actT', {0, 0}, 'recT', {0, 0});
G.score = repmat(emptyScore(), 1, 2);
G.onsetT = inf; G.follow = false; G.unk = false;
G.events0 = {};
end

function G = inject(G, M, scn, follow, unk)
if ischar(scn) || isstring(scn), scn = find(strcmp(M.PP.scen, scn), 1); end
G.E.scn(:) = scn; G.E.onset(:) = G.E.t(1) + 1;
G.E.follow(:) = follow; G.E.unk(:) = unk; G.E.fdelay(:) = 3;
G.E.hop_t(:) = -inf;
G.scn = scn; G.onsetT = G.E.t(1) + 1; G.follow = follow; G.unk = unk;
G.score = repmat(emptyScore(), 1, 2);
G.sides = struct('phase', {'threat', 'threat'}, 'okRun', {0, 0}, 'wasOk', {true, true}, 'detT', {0, 0}, ...
    'confT', {0, 0}, 'actT', {0, 0}, 'recT', {0, 0});
G.events0{end + 1} = sprintf('%s switched on', threatName(M, scn));
end

function G = clearThreat(G)
G.E.onset(:) = inf; G.E.scn(:) = 1; G.scn = 1; G.onsetT = inf;
G.E.follow(:) = false; G.E.unk(:) = false; G.follow = false; G.unk = false;
[G.sides.phase] = deal('clean');
G.events0{end + 1} = 'Threat switched off';
end

%% ===================== Step =====================
function [G, rec] = step(G, M)
PP = M.PP; K = M.K; E0 = G.E;
kinds = {'dqn', 'rule_esc'};
opts = {struct(), struct()};
switch G.right
    case 'none',     kinds{2} = 'fixed'; opts{2}.fixed = M.na;
    case 'operator', kinds{2} = 'fixed'; opts{2}.fixed = G.opcfg;
end
a = zeros(1, 2); d = cell(1, 2);
for i = 1:2
    o = sliceObs(G.obs, i);
    [a(i), G.mem{i}, d{i}] = policy_decide(kinds{i}, o, E0.cfg(i), G.mem{i}, PP, M.agent, opts{i});
end
compPrev = compromised(E0, K, E0.cfg);
[G.E, rw, obsN, info] = link_env('step', E0, PP, K, a);
t = G.E.t(1);
active = t >= G.onsetT;

rec.t = t; rec.scn = G.E.scn(1); rec.threat = PP.scen{rec.scn}; rec.active = active;
rec.s = G.s; rec.ebno = PP.ebno(G.s); rec.r = G.r; rec.follow = G.follow; rec.unk = G.unk;
[rec.emit, rec.th, rec.inr] = emitterSet(M, rec.scn, G.s, G.r, active);
rec.speed = poolSpeed(M, rec.scn, G.s, G.r);
cls_all = cellstr(string(PP.classes(:)'));
side = struct([]);
for i = 1:2
    sd = struct();
    sd.cfg = a(i); sd.act = PP.actions{a(i)};
    sd.switched = info.changed(i); sd.escalated = d{i}.escalated;
    o = sliceObs(G.obs, i);
    sd.probs = o.probs; sd.unknown = o.unknown;
    [sd.conf, ic] = max(o.probs);
    if all(o.probs == 0), sd.cls = 'unknown'; sd.conf = 0; else, sd.cls = cls_all{ic}; end
    sd.monitor = d{i}.cls{1};
    sd.confirmed = d{i}.confirmed; sd.degraded = d{i}.degraded;
    if isempty(d{i}.q), sd.q = []; else, sd.q = d{i}.q(:, 1)'; end
    P = PP.pools{info.sc_eff(i), G.s, info.cfg_eff(i), M.split};
    m = mean(P.ber(P.run == PP.runs{M.split}(G.r)));
    sd.ber = m; sd.ratio = m / max(PP.clean(G.s), K.ber_floor);
    sd.restored = info.restored(i);
    if sd.restored, sd.status = 'ok'; elseif sd.ratio <= 5, sd.status = 'marginal'; else, sd.status = 'lost'; end
    sd.reward = rw(i); sd.q_link = info.q(i); sd.gput = info.gput(i);
    sd.false_sw = info.false_switch(i);
    sd.compromised = info.cfg_eff(i) ~= a(i);
    [G, sd] = channels(G, M, i, a(i), E0.cfg(i), compPrev(i), sd, rec);
    [G, sd] = phaseAndEvents(G, M, i, sd, active, t);
    side = [side, sd]; %#ok<AGROW>
end
rec.side = side;
rec.events = G.events0; G.events0 = {};
G.obs = obsN;
end

function [G, sd] = channels(G, M, i, a, prev, compPrev, sd, rec)
K = M.K;
hop = K.hasCh(a) && (~K.hasCh(prev) || compPrev);
if hop, G.hist(i).hops = G.hist(i).hops + 1; end
if K.hasCh(a)
    G.hist(i).chan = M.hopSeq(mod(G.hist(i).hops - 1, numel(M.hopSeq)) + 1);
else
    G.hist(i).chan = 3;
end
sd.chan = G.hist(i).chan;
sd.chan2 = 0;
if contains(sd.act, 'freq_diversity'), sd.chan2 = mod(sd.chan + 3, 8) + 1; end
comps = strsplit(rec.threat, '+');
sd.chan_jam = 0;
if rec.active && any(ismember(comps, M.inChannel))
    if sd.compromised, sd.chan_jam = sd.chan; else, sd.chan_jam = 3; end
end
sd.hop = hop;
end

function [G, sd] = phaseAndEvents(G, ~, i, sd, active, t)
S = G.sides(i);
ev = {};
if active
    if S.detT == 0 && (~strcmp(sd.monitor, 'none') || sd.degraded)
        S.detT = t;
        if strcmp(sd.cls, 'unknown') || sd.unknown
            ev{end + 1} = 'Detector: unknown signal, watching link quality';
        else
            ev{end + 1} = sprintf('Detector: %s (%.0f%%)', upper(className(sd.cls)), 100 * sd.conf);
        end
    end
    if S.confT == 0 && sd.confirmed, S.confT = t; ev{end + 1} = 'Alarm confirmed twice: response allowed'; end
end
if sd.switched
    if S.actT == 0 && active, S.actT = t; end
    if sd.escalated, ev{end + 1} = 'No improvement: trying a stronger response'; end
    ev{end + 1} = configText(sd.act);
    if sd.false_sw, ev{end + 1} = 'Needless change on a healthy link'; end
end
if sd.compromised && ~G.hist(i).comp, ev{end + 1} = 'Jammer found our new channel'; end
G.hist(i).comp = sd.compromised;
if sd.restored, S.okRun = S.okRun + 1; else, S.okRun = 0; end
if active
    if S.recT == 0 && S.okRun >= 3 && (S.actT > 0 || S.detT > 0)
        S.recT = t; ev{end + 1} = 'Link restored: commands getting through';
    elseif S.wasOk && strcmp(sd.status, 'lost')
        ev{end + 1} = sprintf('Link failing: %.3gx the errors of a clean link', sd.ratio);
    end
end
S.wasOk = ~strcmp(sd.status, 'lost');
if ~active, S.phase = 'clean';
elseif S.recT > 0 && sd.restored, S.phase = 'restored';
elseif S.actT > 0, S.phase = 'acting';
elseif S.confT > 0, S.phase = 'confirmed';
elseif S.detT > 0, S.phase = 'detected';
else, S.phase = 'threat';
end
G.sides(i) = S;
sd.phase = S.phase;
sd.events = ev;
sd.tDet = S.detT - G.onsetT + 1; sd.tConf = S.confT - G.onsetT + 1; sd.tAct = S.actT - G.onsetT + 1; sd.tRec = S.recT - G.onsetT + 1;
if active
    sc = G.score(i);
    sc.n = sc.n + 1; sc.restored = sc.restored + sd.restored; sc.reward = sc.reward + sd.reward;
    sc.switches = sc.switches + sd.switched; sc.false_sw = sc.false_sw + sd.false_sw;
    if S.recT > 0 && isnan(sc.t_rec), sc.t_rec = S.recT - G.onsetT + 1; end
    G.score(i) = sc;
else
    G.score(i).false_sw = G.score(i).false_sw + sd.false_sw;
end
sd.score = G.score(i);
end

function [G, sd] = annotate(G, M, i, sd, rec)
[G, sd] = channels(G, M, i, sd.cfg, sd.prev, false, sd, rec);
[G, sd] = phaseAndEvents(G, M, i, sd, rec.active, rec.t);
end

%% ===================== Scripted episodes =====================
function R = script(M, sc)
% sc: s, r, right, T, onset, threat, follow, unk, seed (optional), clear (cycle, optional)
if ~isfield(sc, 'seed'), sc.seed = 1; end
G = newEpisode(M, struct('s', sc.s, 'r', sc.r, 'right', sc.right, 'seed', sc.seed));
R = cell(1, sc.T);
for k = 1:sc.T
    if k == sc.onset, G = inject(G, M, sc.threat, sc.follow, sc.unk); end
    if isfield(sc, 'clear') && k == sc.clear, G = clearThreat(G); end
    [G, R{k}] = step(G, M);
end
R = [R{:}];
end

%% ===================== Helpers =====================
function o = sliceObs(obs, i)
o = struct('probs', obs.probs(i, :), 'unknown', obs.unknown(i), 'feat', obs.feat(i, :), 'ber', obs.ber(i));
end

function c = compromised(E, K, cfg)
c = E.follow & K.followable(E.scn) & K.hasCh(cfg) & (E.t - E.hop_t) >= E.fdelay & E.t >= E.onset;
end

function [emit, th, inr] = emitterSet(M, scn, s, r, active)
emit = {}; th = []; inr = [];
if ~active, return; end
comps = strsplit(M.PP.scen{scn}, '+');
emit = comps(ismember(comps, M.emitters));
if isempty(emit), return; end
P = M.PP.pools{scn, s, M.na, M.split};
aoa = P.aoa(find(P.run == M.PP.runs{M.split}(r), 1), :);
ebno = M.PP.ebno(s);
for j = 1:numel(emit)
    th(j) = aoa(min(j, numel(aoa))); %#ok<AGROW>
    switch emit{j}
        case 'spoofing',            inr(j) = ebno - M.sev.spoof_sir_db; %#ok<AGROW>
        case 'benign_interference', inr(j) = ebno + M.sev.benign_db; %#ok<AGROW>
        otherwise,                  inr(j) = ebno + M.sev.jsr_db; %#ok<AGROW>
    end
end
end

function v = poolSpeed(M, scn, s, r)
try
    [~, v] = pool_seed(scn, s, M.split, r, M.PP.speed_range);
catch
    v = NaN;
end
end

function sc = emptyScore()
sc = struct('n', 0, 'restored', 0, 'reward', 0, 'switches', 0, 'false_sw', 0, 't_rec', NaN);
end

function s = threatName(M, scn)
s = strjoin(cellfun(@className, strsplit(M.PP.scen{scn}, '+'), 'UniformOutput', false), ' + ');
end

function s = className(c)
switch c
    case 'none',                s = 'clean link';
    case 'jamming',             s = 'barrage jammer';
    case 'reactive_jamming',    s = 'reactive jammer';
    case 'sweeping_jammer',     s = 'sweeping jammer';
    case 'noise_burst',         s = 'noise bursts';
    case 'path_loss',           s = 'path loss';
    case 'spoofing',            s = 'spoofer';
    case 'antenna_fault',       s = 'antenna fault';
    case 'benign_interference', s = 'benign interference';
    otherwise,                  s = strrep(c, '_', ' ');
end
end

function s = configText(a)
parts = strsplit(a, '+');
txt = cellfun(@one, parts, 'UniformOutput', false);
s = strjoin(txt, ' + ');
    function t = one(p)
        switch p
            case 'no_action',         t = 'Back to normal operation';
            case 'channel_switch',    t = 'Hop to a clean channel';
            case 'rate_reduce',       t = 'Slower data rate';
            case 'freq_diversity',    t = 'Send on two channels';
            case 'spatial_diversity', t = 'Antennas null the interferer';
            case 'power_control',     t = 'More transmit power';
            case 'fec_interleave',    t = 'Error-correcting code';
            otherwise,                t = p;
        end
    end
end

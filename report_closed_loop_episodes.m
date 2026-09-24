function report_closed_loop_episodes(draw_figure)
%REPORT_CLOSED_LOOP_EPISODES  Report of results/closed_loop_episodes.mat (D31).
%   Recomputes every episode's outcome from its saved BER trace and switches:
%     not degraded   the 5-cycle BER average never exceeded 2x clean after onset
%                    (the threat did not measurably hurt the link: no recovery to time)
%     pre-configured a countermeasure was already active at onset (a switch before
%                    onset), so the threat met a mitigated link
%     recovered      degraded, then the average returned to <= 2x clean and stayed
%                    there for STAY cycles; T_recover counts from onset
%     not recovered  degraded and never returned within the episode
%   Recovery-time statistics use only degraded, not pre-configured episodes.
%   Writes results/closed_loop_episodes.txt and adds the outcome fields to the .mat;
%   with draw_figure = true also saves results/closed_loop_episodes.png.
if nargin < 1, draw_figure = false; end

f = 'results/closed_loop_episodes.mat';
L = load(f);
MA_LEN = getd(L, 'MA_LEN', 5); STAY = getd(L, 'STAY', 10);
p = load('params.mat').params;
frame_ms = 1e3 * p.frame_duration;
E = L.E; N_PRE = L.N_PRE;
hostile = ~ismember(L.threats, {'benign_interference', 'none'});

%% Classify every episode
for k = 1:numel(E)
    t = find(strcmp(L.threats, E(k).threat), 1);
    s = find(L.EBNO_LIST == E(k).ebno, 1);
    bc = L.clean(s);
    ma = movmean(E(k).trace.ber, [MA_LEN-1 0]);
    post = ma(N_PRE+1:end) > L.RATIO_OK * bc;
    E(k).needs = hostile(t) || L.degraded(t, s);
    E(k).preconf = any(E(k).trace.switch_at <= N_PRE);
    E(k).T_rec = NaN;
    if E(k).preconf
        E(k).status = 'pre-configured';
    elseif ~any(post)
        E(k).status = 'not degraded';
    else
        first_bad = find(post, 1);
        ok = ~post;
        E(k).status = 'not recovered';
        for j = first_bad + 1 : numel(ok) - STAY + 1
            if all(ok(j : j + STAY - 1))
                E(k).status = 'recovered'; E(k).T_rec = j;
                break;
            end
        end
    end
end
timed = @(m) m & ismember({E.status}, {'recovered', 'not recovered'});

%% Report
r = {};
r{end+1} = '=== EPISODIC CLOSED LOOP: RECOVERY TIME IN DECISION CYCLES (proposal KPI #3, D31) ===';
r{end+1} = sprintf('Generated: %s', datestr(now));
r{end+1} = sprintf('%d clean cycles, threat onset, %d cycles after onset | 1 cycle = 1 frame (%.3f ms of signal)', ...
    N_PRE, L.N_POST, frame_ms);
r{end+1} = sprintf('Hysteresis: commit after %d consecutive proposals, no switch within %d cycles of the previous one', L.DWELL, L.HOLD);
r{end+1} = sprintf(['Outcome per episode: recovered (5-cycle BER average back to <= %gx clean for %d cycles, T_recover from onset) | ' ...
    'not recovered | not degraded (never above %gx clean) | pre-configured (countermeasure already active at onset).'], ...
    L.RATIO_OK, STAY, L.RATIO_OK);
r{end+1} = 'T_detect = first cycle with the exact class. Medians in cycles after onset; T_recover over recovered episodes only.';
r{end+1} = '';

r{end+1} = '--- Per threat and Eb/N0 (with hysteresis): DQN vs rule-based ---';
r{end+1} = sprintf('%-20s %6s | %4s %4s %5s %-9s | %4s %4s %5s %-9s', 'threat', 'Eb/N0', ...
    'det', 'act', 'rec', 'R/NR/ND', 'det', 'act', 'rec', 'R/NR/ND');
r{end+1} = sprintf('%-20s %6s | %-26s | %-26s', '', '', 'DQN', 'Rule');
for t = 1:numel(L.threats)
    if strcmp(L.threats{t}, 'none'), continue; end
    for s = 1:numel(L.EBNO_LIST)
        if ~hostile(t) && ~L.degraded(t, s), continue; end
        cD = sel(E, L.threats{t}, L.EBNO_LIST(s), 'dqn | hysteresis');
        cR = sel(E, L.threats{t}, L.EBNO_LIST(s), 'rule | hysteresis');
        r{end+1} = sprintf('%-20s %4g dB | %4s %4s %5s %-9s | %4s %4s %5s %-9s', L.threats{t}, L.EBNO_LIST(s), ...
            med([cD.T_detect]), med([cD.T_act]), med([cD.T_rec]), counts(cD), ...
            med([cR.T_detect]), med([cR.T_act]), med([cR.T_rec]), counts(cR)); %#ok<AGROW>
    end
end
r{end+1} = 'R/NR/ND = recovered / not recovered / not degraded (pre-configured episodes are listed in the summary).';
r{end+1} = '';

r{end+1} = '--- Summary: episodes that need action (hostile, or benign on a degraded link) ---';
r{end+1} = sprintf('%-24s %6s %6s %9s %11s %9s %8s %8s %10s %8s', 'configuration', 'T_act', 'T_rec', ...
    'recovered', 'not recov.', 'not degr.', 'pre-cfg', 'switches', 'final/cln', 'goodput');
for c = 1:numel(L.cfg_keys)
    m = [E.needs] & strcmp({E.cfg}, L.cfg_keys{c});
    mt = timed(m);
    r{end+1} = sprintf('%-24s %6s %6s %5d/%-3d %11d %9d %8d %8.2f %10.2f %8.2f', L.cfg_keys{c}, ...
        med([E(m).T_act]), med([E(mt).T_rec]), sum(strcmp({E(m).status}, 'recovered')), sum(mt), ...
        sum(strcmp({E(m).status}, 'not recovered')), sum(strcmp({E(m).status}, 'not degraded')), ...
        sum([E(m).preconf]), mean([E(m).switches]), median(rmnan([E(m).final_ratio])), mean([E(m).goodput])); %#ok<AGROW>
end
r{end+1} = sprintf('Wall-clock: at ~11 ms decision latency a real-time loop decides every ~%d frames; a median of N cycles is ~N x 11 ms.', ...
    ceil(11 / frame_ms));
r{end+1} = '';

r{end+1} = '--- False alarms: switches on a healthy link ---';
r{end+1} = sprintf('%-24s %20s %24s %20s', 'configuration', 'healthy-link episodes', 'with >= 1 false switch', 'pre-onset switches');
for c = 1:numel(L.cfg_keys)
    mc = strcmp({E.cfg}, L.cfg_keys{c});
    h = mc & ~[E.needs];
    r{end+1} = sprintf('%-24s %20d %24d %20d', L.cfg_keys{c}, sum(h), ...
        sum([E(h).switches] > 0 | [E(h).fa_pre] > 0), sum([E(mc).fa_pre])); %#ok<AGROW>
end
r{end+1} = '';

r{end+1} = '--- Hysteresis effect (proposal risk 8: oscillation) ---';
for c = 1:numel(L.cfg_keys)
    m = [E.needs] & strcmp({E.cfg}, L.cfg_keys{c});
    r{end+1} = sprintf('  %-24s switches after onset %.2f | episodes with > 1 switch %d/%d | pre-configured at onset %d', ...
        L.cfg_keys{c}, mean([E(m).switches]), sum([E(m).switches] > 1), sum(m), sum([E(m).preconf])); %#ok<AGROW>
end

fid = fopen('results/closed_loop_episodes.txt', 'w');
fprintf(fid, '%s\n', r{:});
fclose(fid);
fprintf('%s\n', r{:});
save(f, 'E', '-append');
fprintf('\nSaved results/closed_loop_episodes.txt (outcome fields added to %s)\n', f);
if draw_figure, plot_episodes(); end
end

function c = sel(E, threat, ebno, cfg)
c = E(strcmp({E.threat}, threat) & [E.ebno] == ebno & strcmp({E.cfg}, cfg));
end

function s = counts(c)
s = sprintf('%d/%d/%d', sum(strcmp({c.status}, 'recovered')), sum(strcmp({c.status}, 'not recovered')), ...
    sum(strcmp({c.status}, 'not degraded')));
end

function s = med(x)
x = x(~isnan(x));
if isempty(x), s = '-'; else, s = sprintf('%.0f', median(x)); end
end

function y = rmnan(x)
y = x(~isnan(x));
end

function v = getd(S, name, default)
if isfield(S, name), v = S.(name); else, v = default; end
end

function plot_episodes()
% Example episodes: three threats at 4 dB, first episode, all four configurations:
% 5-cycle BER average relative to clean, onset, 2x-clean line, committed switches.

L = load('results/closed_loop_episodes.mat');
if ~isfield(L, 'MA_LEN'), L.MA_LEN = 5; end
show = {'jamming', 'noise_burst', 'antenna_fault'};
s4 = find(L.EBNO_LIST == 4, 1); if isempty(s4), s4 = 1; end
nC = numel(L.cfg_keys);
cols = [0.00 0.45 0.74; 0.30 0.75 0.93; 0.85 0.33 0.10; 0.93 0.69 0.13];

fig = figure('Position', [60 60 1300 780], 'Color', 'w');
for k = 1:numel(show)
    ax = subplot(numel(show), 1, k); hold(ax, 'on');
    for c = 1:nC
        e = L.E(strcmp({L.E.threat}, show{k}) & [L.E.ebno] == L.EBNO_LIST(s4) & ...
            strcmp({L.E.cfg}, L.cfg_keys{c}) & [L.E.ep] == 1);
        if isempty(e), continue; end
        ma = movmean(e.trace.ber, [L.MA_LEN-1 0]) / L.clean(s4);
        plot(ax, 1:numel(ma), ma, '-', 'Color', cols(c, :), 'LineWidth', 1.3, 'DisplayName', L.cfg_keys{c});
        sw = e.trace.switch_at;
        if ~isempty(sw)
            plot(ax, sw, ma(sw), 'o', 'Color', cols(c, :), 'MarkerFaceColor', cols(c, :), 'HandleVisibility', 'off');
        end
    end
    xline(ax, L.N_PRE + 0.5, 'k--', 'onset', 'HandleVisibility', 'off');
    yline(ax, L.RATIO_OK, 'g:', '2x clean', 'HandleVisibility', 'off');
    set(ax, 'YScale', 'log'); grid(ax, 'on');
    ylabel(ax, 'BER / clean (5-cycle avg)');
    title(ax, sprintf('%s @ %g dB (dots = committed switches)', strrep(show{k}, '_', '\_'), L.EBNO_LIST(s4)));
    if k == 1, legend(ax, 'Location', 'northeast'); end
end
xlabel(ax, 'Decision cycle (frame)');
saveas(fig, 'results/closed_loop_episodes.png'); close(fig);
fprintf('Saved results/closed_loop_episodes.png\n');
end

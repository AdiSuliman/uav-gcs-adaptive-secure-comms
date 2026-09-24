function plot_closed_loop_episodes()
%PLOT_CLOSED_LOOP_EPISODES  Example episodes from results/closed_loop_episodes.mat.
%   Three threats at 4 dB, first episode, all four configurations: 5-cycle BER
%   average relative to clean, threat onset, 2x-clean line, committed switches.
%   A function, so no workspace variable can shadow a MATLAB function here.

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

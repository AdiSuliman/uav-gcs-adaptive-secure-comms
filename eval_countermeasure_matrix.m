%% EVAL_COUNTERMEASURE_MATRIX.m — action efficacy per threat (D28)
% Every threat (nominal severity) x every action x Eb/N0, through the real
% Simulink link with apply_countermeasure.m. Ground truth is used for the threat
% (no detector, no policy): this measures what each action CAN do, which is the
% physical basis for the DQN reward, the rule-based baseline and the
% survivability map.
%
% Outputs: results/countermeasure_matrix.{txt,mat,png}

%% Setup
init_params;
p0 = load('params.mat').params;
modelName  = 'UAV_GCS_Threat_Link';
delay_bits = 20;
SNR_LIST   = [0 4 10];
RATIO_OK = 2; RATIO_MARG = 5;

threats = {'jamming','reactive_jamming','sweeping_jammer','noise_burst','path_loss', ...
           'spoofing','antenna_fault','benign_interference','none'};
actions = {'no_action','channel_switch','rate_reduce','freq_diversity','spatial_diversity'};
nT = numel(threats); nA = numel(actions); nS = numel(SNR_LIST);

ber   = nan(nT, nA, nS);
gp    = ones(1, nA);
bw    = ones(1, nA);
t0 = tic;

%% Simulate: one rebuild per (threat, action), Eb/N0 set on the AWGN block
for t = 1:nT
    threat = threats{t};
    p = p0; p.active_threat = threat;
    for a = 1:nA
        [p2, g_db, cm] = apply_countermeasure(p, threat, actions{a});
        gp(a) = cm.goodput_factor; bw(a) = cm.bw_factor;
        params = p2; save('params.mat', 'params');
        evalc('build_threat_model');
        for s = 1:nS
            snr_dB = SNR_LIST(s) + 10*log10(p2.bits_per_symbol) - 10*log10(p2.sps);
            set_param([modelName '/AWGN'], 'SNR', num2str(snr_dB + g_db), 'SignalPower', num2str(1/p2.sps));
            out = sim(modelName);
            [~, ber_f] = extract_closed_loop_frames(out, p2, delay_bits);
            ber(t, a, s) = mean(ber_f, 'omitnan');
        end
    end
    fprintf('  [%d/%d] %-20s done (%.1f min)\n', t, nT, threat, toc(t0)/60);
end
params = p0; save('params.mat', 'params');

%% Score against the clean link (none + no_action at the same Eb/N0)
clean = squeeze(ber(strcmp(threats, 'none'), 1, :))';
ratio = ber ./ reshape(clean, 1, 1, nS);
rec   = nan(nT, nA, nS);
for t = 1:nT
    for a = 1:nA
        for s = 1:nS
            rec(t, a, s) = recovery_vs_clean(ber(t, 1, s), ber(t, a, s), clean(s));
        end
    end
end

%% Report
report = {};
report{end+1} = '=== COUNTERMEASURE EFFICACY MATRIX (D28, nominal severity, ground-truth threat) ===';
report{end+1} = sprintf('Generated: %s | acr %g dB | rate / %g | %d Rx antennas', datestr(now), ...
    p0.cm_acr_db, p0.cm_rate_factor, p0.cm_n_rx);
report{end+1} = sprintf('Cell = BER_after / BER_clean (<= %g restored, <= %g marginal). * = best action, R = rule-based choice.', RATIO_OK, RATIO_MARG);
report{end+1} = sprintf('Costs: goodput x%s | spectrum x%s  (order: %s)', mat2str(gp, 2), mat2str(bw), strjoin(actions, ', '));
for s = 1:nS
    report{end+1} = '';
    report{end+1} = sprintf('--- Eb/N0 = %g dB (clean BER %.3e) ---', SNR_LIST(s), clean(s));
    hdr = sprintf('%-20s', 'threat');
    for a = 1:nA, hdr = [hdr sprintf('%19s', actions{a})]; end %#ok<AGROW>
    report{end+1} = hdr;
    for t = 1:nT
        [~, best] = min(ber(t, :, s));
        rule = rule_based_policy(threats{t});
        line = sprintf('%-20s', threats{t});
        for a = 1:nA
            tag = '';
            if a == best, tag = [tag '*']; end %#ok<AGROW>
            if strcmp(actions{a}, rule), tag = [tag 'R']; end %#ok<AGROW>
            line = [line sprintf('%19s', sprintf('%.2fx%s', ratio(t, a, s), tag))]; %#ok<AGROW>
        end
        report{end+1} = line; %#ok<SAGROW>
    end
end
report{end+1} = '';
report{end+1} = '--- Best achievable link state per threat (any action) ---';
for t = 1:nT
    if ismember(threats{t}, {'none','benign_interference'}), continue; end
    parts = {};
    for s = 1:nS
        [r, best] = min(ratio(t, :, s));
        if r <= RATIO_OK, st = 'restored'; elseif r <= RATIO_MARG, st = 'marginal'; else, st = 'NOT restored'; end
        parts{end+1} = sprintf('%gdB %s %.2fx (%s)', SNR_LIST(s), actions{best}, r, st); %#ok<SAGROW>
    end
    report{end+1} = sprintf('  %-20s %s', threats{t}, strjoin(parts, ' | ')); %#ok<SAGROW>
end

if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/countermeasure_matrix.txt', 'w');
fprintf(fid, '%s\n', report{:});
fclose(fid);
fprintf('%s\n', report{:});
save('results/countermeasure_matrix.mat', 'ber', 'ratio', 'rec', 'clean', 'threats', 'actions', ...
    'SNR_LIST', 'gp', 'bw', 'RATIO_OK', 'RATIO_MARG');

%% Figure: log10(BER / clean) heatmap per Eb/N0
fig = figure('Position', [80 80 1300 420], 'Color', 'w');
for s = 1:nS
    subplot(1, nS, s);
    imagesc(log10(ratio(:, :, s)));
    caxis([0 log10(50)]); colormap(flipud(hot));
    set(gca, 'XTick', 1:nA, 'XTickLabel', strrep(actions, '_', '\_'), 'XTickLabelRotation', 30, ...
        'YTick', 1:nT, 'YTickLabel', strrep(threats, '_', '\_'));
    for t = 1:nT
        for a = 1:nA
            text(a, t, sprintf('%.1f', ratio(t, a, s)), 'HorizontalAlignment', 'center', 'FontSize', 7);
        end
    end
    title(sprintf('BER / clean at E_b/N_0 = %g dB', SNR_LIST(s)));
end
cb = colorbar; cb.Label.String = 'log_{10}(BER / clean)';
saveas(fig, 'results/countermeasure_matrix.png'); close(fig);
fprintf('Saved results/countermeasure_matrix.{txt,mat,png} (%.1f min)\n', toc(t0)/60);

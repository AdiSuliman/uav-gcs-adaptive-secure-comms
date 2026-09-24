%% C2 — TRAIN DQN AGENT
% Reward table measured through the real Simulink link for every threat x
% action x Eb/N0 (D29), with each action applied by apply_countermeasure.m (D28).
% Reward = link state against the clean link (D27) minus the action's cost;
% acting on a healthy non-hostile link is a false alarm. Episodes sample
% (threat, Eb/N0) cells and real per-frame link states, so no simulation runs
% inside the training loop. A validation gate checks every cell before saving.
close all; clc;
fprintf('=== C2: Train DQN Agent ===\n\n');

rng(42, 'twister');

%% 1. Agent, threats, actions
agent = dqn_agent();
action_names = agent.action_names;
na = find(strcmp(action_names, 'no_action'), 1);
nA = numel(action_names);

% Order must match the threat_list inside build_dqn_state.m
threat_list = {'jamming', 'reactive_jamming', 'sweeping_jammer', 'noise_burst', ...
               'path_loss', 'spoofing', 'antenna_fault', 'benign_interference', 'none'};
num_threats = numel(threat_list);
hostile = ~ismember(threat_list, {'benign_interference', 'none'});

init_params;
p0 = load('params.mat').params;
modelName  = 'UAV_GCS_Threat_Link';
delay_bits = 20;
SNR_LIST = p0.EbNo_dB;
nS = numel(SNR_LIST);

% Reward design (D29)
RW = struct( ...
    'RATIO_OK',   2, ...     % link degraded if BER > 2x clean (survivability-map threshold)
    'R_TOL',      1.15, ...  % BER within 15% of clean counts as fully restored (draw-to-draw spread, D27)
    'L_GP',       0.30, ...  % cost per unit of goodput lost (rate/4 -> 22.5 points)
    'L_BW',       0.05, ...  % cost per extra channel occupied (2x spectrum -> 5 points)
    'FA_PENALTY', 40);       % any action on a healthy non-hostile link

%% 2. Measure BER for every threat x action x Eb/N0
fprintf('Measuring the link for %d threats x %d actions x %d Eb/N0 points...\n\n', num_threats, nA, nS);
ber_tab = nan(num_threats, nA, nS);
frames  = cell(num_threats, nS);         % per-frame [BER, RSSI, PLR] of the unmitigated run (training states)
gp = ones(1, nA); bw = ones(1, nA);
t0 = tic;
for ti = 1:num_threats
    threat = threat_list{ti};
    p = p0; p.active_threat = threat;
    for ai = 1:nA
        [p2, g_db, cm] = apply_countermeasure(p, threat, action_names{ai});
        gp(ai) = cm.goodput_factor; bw(ai) = cm.bw_factor;
        params = p2; save('params.mat', 'params');
        evalc('build_threat_model');
        for s = 1:nS
            snr_dB = SNR_LIST(s) + 10*log10(p2.bits_per_symbol) - 10*log10(p2.sps);
            set_param([modelName '/AWGN'], 'SNR', num2str(snr_dB + g_db), 'SignalPower', num2str(1/p2.sps));
            out = sim(modelName);
            [~, ber_f, rssi_f, plr_f] = extract_closed_loop_frames(out, p2, delay_bits);
            ber_tab(ti, ai, s) = mean(ber_f, 'omitnan');
            if ai == na
                b = ber_f(:); r = rssi_f(:); q = plr_f(:);
                v = ~isnan(b);
                r(isnan(r)) = 0; q(isnan(q)) = 0;
                frames{ti, s} = [b(v) r(v) q(v)];
            end
        end
    end
    fprintf('  [%d/%d] %-20s measured (%.1f min)\n', ti, num_threats, threat, toc(t0)/60);
end
params = p0; save('params.mat', 'params');

%% 2b. Countermeasure efficacy matrix (results/countermeasure_matrix.*, D28)
% BER after each action relative to the clean link, per threat and Eb/N0, from the
% measurements above (ground-truth threat, nominal severity).
clean_m = squeeze(ber_tab(strcmp(threat_list, 'none'), na, :))';
ratio_m = ber_tab ./ reshape(clean_m, 1, 1, nS);
rep = {};
rep{end+1} = '=== COUNTERMEASURE EFFICACY MATRIX (D28, nominal severity, ground-truth threat) ===';
rep{end+1} = sprintf('Generated: %s by train_dqn.m | acr %g dB | rate / %g | %d Rx antennas', datestr(now), ...
    p0.cm_acr_db, p0.cm_rate_factor, p0.cm_n_rx);
rep{end+1} = 'Cell = BER_after / BER_clean (<= 2 restored, <= 5 marginal). * = best action, R = rule-based choice.';
rep{end+1} = sprintf('Costs: goodput x%s | spectrum x%s  (order: %s)', mat2str(gp, 2), mat2str(bw), strjoin(action_names, ', '));
for s = 1:nS
    rep{end+1} = ''; %#ok<SAGROW>
    rep{end+1} = sprintf('--- Eb/N0 = %g dB (clean BER %.3e) ---', SNR_LIST(s), clean_m(s)); %#ok<SAGROW>
    hdr = sprintf('%-20s', 'threat');
    for ai = 1:nA, hdr = [hdr sprintf('%19s', action_names{ai})]; end %#ok<AGROW>
    rep{end+1} = hdr; %#ok<SAGROW>
    for ti = 1:num_threats
        [~, best] = min(ber_tab(ti, :, s));
        rule = rule_based_policy(threat_list{ti});
        line = sprintf('%-20s', threat_list{ti});
        for ai = 1:nA
            tag = '';
            if ai == best, tag = [tag '*']; end %#ok<AGROW>
            if strcmp(action_names{ai}, rule), tag = [tag 'R']; end %#ok<AGROW>
            line = [line sprintf('%19s', sprintf('%.2fx%s', ratio_m(ti, ai, s), tag))]; %#ok<AGROW>
        end
        rep{end+1} = line; %#ok<SAGROW>
    end
end
if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/countermeasure_matrix.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fig_m = figure('Position', [60 60 1400 700], 'Color', 'w');
for s = 1:nS
    subplot(2, ceil(nS/2), s);
    imagesc(log10(ratio_m(:, :, s)), [0 log10(50)]); colormap(gca, flipud(hot));
    set(gca, 'XTick', 1:nA, 'XTickLabel', strrep(action_names, '_', '\_'), 'XTickLabelRotation', 30, ...
        'YTick', 1:num_threats, 'YTickLabel', strrep(threat_list, '_', '\_'), 'FontSize', 7);
    for ti = 1:num_threats
        for ai = 1:nA
            text(ai, ti, sprintf('%.1f', ratio_m(ti, ai, s)), 'HorizontalAlignment', 'center', 'FontSize', 7);
        end
    end
    title(sprintf('BER / clean, E_b/N_0 = %g dB', SNR_LIST(s)));
end
saveas(fig_m, 'results/countermeasure_matrix.png'); close(fig_m);
fprintf('Saved results/countermeasure_matrix.{txt,png}\n\n');

%% 3. Reward table
clean = squeeze(ber_tab(strcmp(threat_list, 'none'), na, :));
reward_table = zeros(num_threats, nA, nS);
must_act = false(num_threats, nS);
for ti = 1:num_threats
    for s = 1:nS
        rb = ber_tab(ti, na, s) / clean(s);
        must_act(ti, s) = hostile(ti) || rb > RW.RATIO_OK;
        for ai = 1:nA
            reward_table(ti, ai, s) = reward_of(ber_tab(ti, na, s), ber_tab(ti, ai, s), clean(s), ...
                gp(ai), bw(ai), ai == na, must_act(ti, s), RW);
        end
    end
end

fprintf('\nBest action per (threat, Eb/N0) by reward:\n');
snr_hdr = arrayfun(@(x) sprintf('%gdB', x), SNR_LIST, 'UniformOutput', false);
fprintf('%-20s', 'threat'); fprintf('%18s', snr_hdr{:}); fprintf('\n');
for ti = 1:num_threats
    fprintf('%-20s', threat_list{ti});
    for s = 1:nS
        [rbest, abest] = max(reward_table(ti, :, s));
        fprintf('%18s', sprintf('%s %.0f', short_name(action_names{abest}), rbest));
    end
    fprintf('\n');
end

if ~exist('results', 'dir'), mkdir('results'); end
fig0 = figure('Position', [60 60 1400 700], 'Color', 'w');
for s = 1:nS
    subplot(2, ceil(nS/2), s);
    imagesc(reward_table(:, :, s), [-RW.FA_PENALTY 100]); colormap(parula);
    set(gca, 'XTick', 1:nA, 'XTickLabel', strrep(action_names, '_', '\_'), 'XTickLabelRotation', 30, ...
        'YTick', 1:num_threats, 'YTickLabel', strrep(threat_list, '_', '\_'), 'FontSize', 7);
    for ti = 1:num_threats
        for ai = 1:nA
            text(ai, ti, sprintf('%.0f', reward_table(ti, ai, s)), 'HorizontalAlignment', 'center', 'FontSize', 7);
        end
    end
    title(sprintf('Reward, E_b/N_0 = %g dB', SNR_LIST(s)));
end
saveas(fig0, 'results/dqn_reward_table.png'); close(fig0);
fprintf('\nSaved results/dqn_reward_table.png\n\n');

%% 4. Training: episodes sample (threat, Eb/N0) cells and real per-frame states
N_EPISODES = 4000;
P_UNKNOWN  = 0.10;                      % share of episodes with the class hidden (proposal risk 13)
w = ones(1, num_threats);
w(ismember(threat_list, {'antenna_fault', 'benign_interference', 'none'})) = 2;
cw = cumsum(w) / sum(w);

nState = agent.numStates;
buf_S = zeros(N_EPISODES, nState); buf_A = zeros(N_EPISODES, 1); buf_R = zeros(N_EPISODES, 1);
training_loss = [];
avgG = []; avgSqG = [];
episode_rewards = zeros(1, N_EPISODES);
avg_rewards_per_episode = [];

fprintf('Training on %d episodes...\n', N_EPISODES);
for ep = 1:N_EPISODES
    ti = find(rand < cw, 1);
    s  = randi(nS);
    fr = frames{ti, s};
    k  = randi(size(fr, 1));
    cls = threat_list{ti};
    if rand < P_UNKNOWN, cls = 'unknown'; end

    state  = build_dqn_state(cls, fr(k, 1), fr(k, 2), SNR_LIST(s), fr(k, 3));
    action = selectAction(agent, state, true);
    reward = reward_table(ti, action, s);

    buf_S(ep, :) = state'; buf_A(ep) = action; buf_R(ep) = reward;
    episode_rewards(ep) = reward;

    if ep >= agent.batch_size
        idx = randperm(ep, agent.batch_size);
        S = single(buf_S(idx, :)');
        A = buf_A(idx);
        target = single(buf_R(idx)');         % one-shot episodes: target = reward
        [loss, grads] = dlfeval(@qLoss, agent.qNetwork, dlarray(S, 'CB'), A, target);
        [agent.qNetwork, avgG, avgSqG] = adamupdate(agent.qNetwork, grads, avgG, avgSqG, ...
            ep - agent.batch_size + 1, agent.learning_rate);
        training_loss(end+1) = double(extractdata(loss)); %#ok<SAGROW>
    end

    agent.epsilon = max(agent.epsilon_min, agent.epsilon * agent.epsilon_decay);

    if mod(ep, 200) == 0
        avg_rewards_per_episode(end+1) = mean(episode_rewards(ep-199:ep)); %#ok<SAGROW>
        fprintf('  Episode %4d/%d: avg reward %.1f, epsilon %.3f\n', ep, N_EPISODES, ...
            avg_rewards_per_episode(end), agent.epsilon);
    end
end

%% 5. Validation gate over every (threat, Eb/N0) cell
% Hard failures: acting on 'none' or on benign interference that leaves the
% link near clean (<= 1.5x); choosing no_action where acting is worth >= 30
% reward points. Cells near the 2x boundary are reported by regret only.
fprintf('\nValidation gate (median frame state per cell):\n');
chosen_tab = cell(num_threats, nS);
regret = zeros(num_threats, nS);
gate_pass = true;
fails = {};
for ti = 1:num_threats
    for s = 1:nS
        fr = frames{ti, s};
        st = build_dqn_state(threat_list{ti}, median(fr(:, 1)), median(fr(:, 2)), SNR_LIST(s), mean(fr(:, 3)));
        qv = extractdata(predict(agent.qNetwork, dlarray(single(st), 'CB')));
        [~, a] = max(qv);
        R = squeeze(reward_table(ti, :, s));
        chosen_tab{ti, s} = action_names{a};
        regret(ti, s) = max(R) - R(a);
        rb = ber_tab(ti, na, s) / clean(s);
        isFA   = a ~= na && (strcmp(threat_list{ti}, 'none') || ...
                 (strcmp(threat_list{ti}, 'benign_interference') && rb <= 1.5));
        isMiss = a == na && must_act(ti, s) && max(R) >= 30;
        if isFA || isMiss
            gate_pass = false;
            fails{end+1} = sprintf('%s @ %g dB -> %s (%s)', threat_list{ti}, SNR_LIST(s), ...
                action_names{a}, ternary(isFA, 'false alarm', 'missed action')); %#ok<SAGROW>
        end
    end
end
fprintf('%-20s', 'threat'); fprintf('%22s', snr_hdr{:}); fprintf('\n');
for ti = 1:num_threats
    fprintf('%-20s', threat_list{ti});
    for s = 1:nS
        fprintf('%22s', sprintf('%s (regret %.0f)', short_name(chosen_tab{ti, s}), regret(ti, s)));
    end
    fprintf('\n');
end
fprintf('Mean regret %.1f | cells with regret > 15: %d/%d\n', mean(regret(:)), sum(regret(:) > 15), numel(regret));

if ~gate_pass
    fprintf('Gate failures:\n'); fprintf('  %s\n', fails{:});
    error('Validation gate FAILED -- NOT saving trained_dqn.mat. Rerun (another rng seed) if it repeats.');
end
fprintf('Validation gate PASSED.\n\n');

%% 6. Save
save('data/trained_dqn.mat', 'agent', 'reward_table', 'ber_tab', 'clean', 'SNR_LIST', ...
    'threat_list', 'action_names', 'RW', 'gp', 'bw', 'regret', 'chosen_tab', '-v7.3');
fprintf('Saved data/trained_dqn.mat\n');

%% 7. Training curves
fig = figure('Position', [100 100 900 400], 'Color', 'w');
subplot(1, 2, 1);
plot(training_loss, 'b-'); xlabel('Update'); ylabel('Q-loss'); title('DQN training loss'); grid on;
subplot(1, 2, 2);
plot((1:numel(avg_rewards_per_episode)) * 200, avg_rewards_per_episode, 'g-', 'LineWidth', 1.5);
xlabel('Episode'); ylabel('Average reward (200 episodes)'); title('DQN average reward'); grid on;
sgtitle('C2: DQN Training Curves');
saveas(fig, 'results/dqn_training_curves.png'); close(fig);
fprintf('Saved results/dqn_training_curves.png\n\n=== C2 Complete ===\n');

%% Local functions
function r = reward_of(bb, ba, bc, gpf, bwf, isNoAction, mustAct, RW)
% Reward of one action in one (threat, Eb/N0) cell.
if ~mustAct                               % healthy non-hostile link: acting is an unnecessary switch
    r = 0;
    if ~isNoAction, r = -RW.FA_PENALTY; end
    return;
end
if isNoAction
    r = 0;
    return;
end
if ba / bc <= RW.R_TOL
    score = 100;
else
    score = recovery_vs_clean(bb, ba, bc);
    if isnan(score), score = 0; end
end
r = score - 100 * (RW.L_GP * (1 - gpf) + RW.L_BW * (bwf - 1));
end

function [loss, gradients] = qLoss(qNet, S, A, target)
Q_pred = forward(qNet, S);
idx = sub2ind(size(Q_pred), A(:)', 1:numel(A));
loss = mean((Q_pred(idx) - target).^2, 'all');
gradients = dlgradient(loss, qNet.Learnables);
end

function y = selectAction(agent, state, training)
if training && rand() < agent.epsilon
    y = randi(numel(agent.action_names));
else
    qvals = predict(agent.qNetwork, dlarray(single(state), 'CB'));
    [~, y] = max(extractdata(qvals), [], 1);
end
end

function s = short_name(a)
s = strrep(strrep(strrep(a, 'channel_', 'ch_'), '_diversity', '_div'), 'no_action', 'none');
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end

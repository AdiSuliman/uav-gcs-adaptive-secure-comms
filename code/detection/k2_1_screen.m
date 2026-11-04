%% K21 - K2_1_SCREEN: D111's gate K2-1, the cue-only novelty on validation
% For each held-out threat k of eval_ood_detection.m's folds (ood_loto_split.m 'masks': the same
% halves, labels and exclusion of k's sub-runs), the validation AUROC of cue-Maha alone: the
% physics row of every window (ood_cue.m over the fusion window N of data/fusion.mat, the level
% step over TW = 10 frames when N is shorter, D111 point 4), scaled by the median and IQR of the
% fit windows and clipped at +-10, a class-conditional Gaussian with tied covariance and 10%
% shrinkage (Lee et al. 2018, eqs. 1-2) fitted on the known classes' training windows without
% k's sub-runs, read on the selection half's known windows against k's validation windows,
% every window labelled by its newest frame. No network is retrained and no variant is chosen.
% The gate (ood_k2_rules.m 'k21_go'): K2-2 is built only if this AUROC is >= 0.80 on at least 2
% of path_loss, jamming, antenna_fault and airframe_shadowing and >= 0.70 on their mean.
% Beside the gate, descriptive only: the same AUROC on the windows whose cue window is full
% (the monitor's window, max(N, ood.win, 10), filled), the only ones where K2-2's U reads the cue
% (p_cue = 1 before, D111 item 7), with their share of the known and held-out windows.
% The margin basis of D111 item 6, printed first: the 18.10 run's per-threat validation AUROC of
% the registered statistic C0 (last_or_if over 1 cycle, OOD_1810, default
% results/ood_detection.mat) and its standard error by clusters. That run kept no per-window
% values, so the error is Hanley & McNeil's (Radiology 1982, eq. 2) with the sub-runs as the
% units (windows fully correlated inside a sub-run, the larger error), the same with the windows
% as the units beside it (independent windows, the smaller); cue-Maha's own cluster bootstrap
% error on the same windows (sub-runs resampled, 2000 draws) is printed beside.
% It starts only on the docs commit that registers D110-D118 (REG_COMMIT, DOCS_REPO or
% profile.json; ood_k2_rules.m 'registered') and prints that commit, the code's commit and the
% SHA-256 of its rule code and of its inputs. It never loads data/splits_fresh*.mat (load_split):
% it reads data/splits.mat, data/fusion.mat's N, data/trained_detector.mat's ood and the 18.10
% file only, under K21_SRC (default the current folder; a profile's tree read in place), and
% writes results/k2_1_screen.{txt,mat} under the current folder only.
% Disclosed (D111 item 1): it reads every held-out threat's validation windows, so the build
% decision is not nested; the four threats were named from the second test set's table.
% Output: results/k2_1_screen.{txt,mat}

close all; clc;
fprintf('=== K2-1: cue-only novelty screen (D111 item 1) ===\n\n');
if ~exist('REG_COMMIT', 'var'), REG_COMMIT = ''; end
if ~exist('DOCS_REPO', 'var'), DOCS_REPO = ''; end
if ~exist('K21_SRC', 'var'), K21_SRC = pwd; end
if ~exist('OOD_1810', 'var'), OOD_1810 = fullfile(K21_SRC, 'results', 'ood_detection.mat'); end
[reg, reg_txt] = ood_k2_rules('registered', DOCS_REPO, REG_COMMIT);
[cm, tr] = ood_k2_rules('commit');
NB = 2000;                                              % bootstrap draws
IN = {fullfile(K21_SRC, 'data', 'splits.mat'), fullfile(K21_SRC, 'data', 'fusion.mat'), ...
    fullfile(K21_SRC, 'data', 'trained_detector.mat'), OOD_1810};
rep = [{'=== K2-1: CUE-ONLY NOVELTY SCREEN (D111 item 1) ===', sprintf('Generated: %s | commit %s | code_tree %s', ...
    datestr(now), cm, tr), reg_txt}, ood_k2_rules('sha', {'k2_1_screen.m', 'ood_cue.m', 'ood_k2_rules.m', 'ood_loto_split.m'}), ...
    cellfun(@(f) sprintf('input %s sha256 %s', f, kpi6_fresh_marker('sha', f)), IN, 'UniformOutput', false)];
fprintf('%s\n', rep{:});
n0 = numel(rep);

%% 1. The 18.10 run's C0 on validation (the margin basis)
O = load(OOD_1810, 'R', 'SC');
held = {O.R.held_out};
j0 = find(strcmp(O.SC, 'last_or_if'));
A0 = arrayfun(@(r) r.auroc_val(j0), O.R);               % one cycle: the frame alone

%% 2. The cue rows of every training and validation window
S = load_split(IN{1}); sp = S.splits; clear S
sp.test = []; sp.train.X = []; sp.val.X = [];           % no image is read
Lf = load(IN{2}, 'N'); N = Lf.N;                        % the fusion window (fusion_model.m)
Dt = load(IN{3}, 'ood');
W0 = 1; if isfield(Dt.ood, 'win') && ~isempty(Dt.ood.win), W0 = Dt.ood.win; end
C = numel(sp.classes); Ns = ood_cue('step_n', N);
NW = max([N, W0, window_cues('branch_window'), Ns]);   % the monitor's window with FM.unk (policy_monitor.m)
Xtr = ood_cue('split', sp.train, sp.norm.feat_names, C, N);
Xva = ood_cue('split', sp.val, sp.norm.feat_names, C, N);
fw = ood_cue('fill', sp.val.run, sp.val.pos) >= NW;
static_ok = ood_k2_rules('static', ood_cue('names', C));
assert(static_ok, 'k2_1_screen:static', 'the cue row holds a probability, label or truth column');
fprintf('Cue rows: %d training and %d validation windows, %d columns, fusion window N = %d, level step over %d\n', ...
    size(Xtr, 1), size(Xva, 1), size(Xtr, 2), N, max(N, Ns));

%% 3. cue-Maha per held-out threat
T = numel(held);
[a, af, se_b, n_kr, n_ur, n_kw, n_uw, fk, fu] = deal(nan(1, T));
for h = 1:T
    F = ood_loto_split('masks', sp, held{h});
    Sc = ood_cue('scale_fit', Xtr(F.tr, :));
    Mm = ood_cue('maha_fit', ood_cue('scale', Sc, Xtr(F.tr, :)), F.ytr(F.tr));
    s = ood_cue('maha', Mm, ood_cue('scale', Sc, Xva));
    a(h) = ood_k2_rules('auroc', s(F.kn), s(F.un));
    af(h) = ood_k2_rules('auroc', s(F.kn & fw), s(F.un & fw));
    fk(h) = mean(fw(F.kn)); fu(h) = mean(fw(F.un));
    B = ood_k2_rules('boot_auroc', s, F.kn, F.un, sp.val.run, NB, 9100 + h);
    se_b(h) = std(B);
    n_kr(h) = numel(unique(sp.val.run(F.kn))); n_ur(h) = numel(unique(sp.val.run(F.un)));
    n_kw(h) = sum(F.kn); n_uw(h) = sum(F.un);
    fprintf('[%d/%d] %-20s cue-Maha validation AUROC %.3f\n', h, T, held{h}, a(h));
end
se_r = hanley_mcneil(A0, n_kr, n_ur); se_w = hanley_mcneil(A0, n_kw, n_uw);

%% 4. Report and the gate
rep{end+1} = '';
rep{end+1} = sprintf(['Margin basis (D111 item 6), the 18.10 run''s registered statistic C0 (%s, last_or_if over 1 cycle): ' ...
    'validation AUROC and its standard error, Hanley & McNeil with the sub-runs / the windows as the units (no per-window ' ...
    'values kept by that run); cue-Maha''s cluster bootstrap error (%d draws) beside:'], OOD_1810, NB);
rep{end+1} = sprintf('%-20s %8s %10s %10s %10s %10s %11s %13s', 'held-out threat', 'C0 AUROC', 'SE runs', 'SE windows', ...
    'cue-Maha', 'boot SE', 'runs k/u', 'windows k/u');
for h = 1:T
    rep{end+1} = sprintf('%-20s %8.3f %10.4f %10.4f %10.3f %10.4f %5d/%-5d %6d/%-6d', held{h}, A0(h), se_r(h), se_w(h), ...
        a(h), se_b(h), n_kr(h), n_ur(h), n_kw(h), n_uw(h)); %#ok<SAGROW>
end
rep{end+1} = sprintf(['mean C0 AUROC %.3f (SE of the mean, sub-runs as units %.4f); mean cue-Maha %.3f. Disclosed: the screen ' ...
    'reads every held-out threat''s validation windows (not nested); the four gate threats were named from the second ' ...
    'test set''s table; the value D111 quotes is read on the fourth set, nested over all ten threats.'], mean(A0), ...
    sqrt(sum(se_r.^2)) / T, mean(a));
rep{end+1} = sprintf(['Descriptive, not the gate: cue-Maha on the windows whose cue window of %d cycles is full (U reads the ' ...
    'cue there only, p_cue = 1 before; share of the known / held-out windows): %s'], NW, strjoin(arrayfun(@(h) ...
    sprintf('%s %.3f (%.0f%% / %.0f%%)', held{h}, af(h), 100 * fk(h), 100 * fu(h)), 1:T, 'UniformOutput', false), ', '));
[go, gl] = ood_k2_rules('k21_go', held, a);
rep{end+1} = gl;
if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/k2_1_screen.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('%s\n', rep{n0 + 1:end});
save('results/k2_1_screen.mat', 'held', 'a', 'af', 'fk', 'fu', 'A0', 'se_r', 'se_w', 'se_b', 'n_kr', 'n_ur', 'n_kw', ...
    'n_uw', 'go', 'N', 'Ns', 'NW', 'reg', 'cm', 'tr', 'NB');
fprintf('\nSaved results/k2_1_screen.{txt,mat}\n');


%% ===== Local functions =====
function S = load_split(f)
% The only data file K2-1 loads: never a test set built after the dataset (splits_fresh*.mat).
assert(~contains(f, 'splits_fresh'), 'k2_1_screen:fresh', 'K2-1 never loads %s (D111 item 1)', f);
S = load(f, 'splits');
end

function se = hanley_mcneil(A, n1, n2)
% Standard error of an AUROC A from n1 units of the higher-scoring group and n2 of the other
% (Hanley & McNeil 1982, eq. 2).
Q1 = A ./ (2 - A); Q2 = 2 * A.^2 ./ (1 + A);
se = sqrt((A .* (1 - A) + (n1 - 1) .* (Q1 - A.^2) + (n2 - 1) .* (Q2 - A.^2)) ./ (n1 .* n2));
end

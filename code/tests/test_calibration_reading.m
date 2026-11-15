function tests = test_calibration_reading
%TEST_CALIBRATION_READING  The calibration math of calibration_reading.m on toy cases with known
%   answers, and the reading of a tree whose prediction files hold labels only. Run from the
%   repository root: results = runtests('code/tests/test_calibration_reading.m')
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
end

function test_perfect_confidence(tc)
% Ten frames at confidence 0.9 with nine right: calibrated, ECE 0; the Brier score by hand.
P = repmat([0.9 0.1], 10, 1); y = [ones(9, 1); 2];
C = calibration_reading('stats', P, y);
verifyEqual(tc, C.ece, 0, 'AbsTol', 1e-12);
verifyEqual(tc, C.acc, 0.9, 'AbsTol', 1e-12);
verifyEqual(tc, C.brier, (9 * 0.02 + 1 * (0.81 + 0.81)) / 10, 'AbsTol', 1e-12);
verifyEqual(tc, C.top(14, :), [10 0.9 0.9 0], 'AbsTol', 1e-12);    % 0.9 lies in [13/15, 14/15)
verifyEqual(tc, sum(C.top(:, 1)), 10);
end

function test_overconfident(tc)
% Ten frames at 0.9 with five right: ECE 0.4; per class, class 1's frames at p = 0.9 have
% frequency 0.5 and class 2's at p = 0.1 frequency 0.5: both gaps 0.4.
P = repmat([0.9 0.1], 10, 1); y = [ones(5, 1); 2 * ones(5, 1)];
C = calibration_reading('stats', P, y);
verifyEqual(tc, C.ece, 0.4, 'AbsTol', 1e-12);
verifyEqual(tc, C.brier, (5 * 0.02 + 5 * 1.62) / 10, 'AbsTol', 1e-12);
verifyEqual(tc, [C.cls.ece], [0.4 0.4], 'AbsTol', 1e-12);
verifyEqual(tc, [C.cls.n_pos], [5 5]);
verifyEqual(tc, C.cls(2).table(2, :), [10 0.1 0.5], 'AbsTol', 1e-12);   % 0.1 lies in [1/15, 2/15)
end

function test_two_bins_and_renormalization(tc)
% Two confidence groups: 0.6 (4 frames, 2 right) and 1.0 (4 frames, 4 right); rows that do not
% sum to 1 are renormalized and their largest deviation reported.
P = [repmat([0.6 0.4 0], 4, 1); repmat([0 0 2], 4, 1)];
y = [1; 1; 2; 2; 3; 3; 3; 3];
C = calibration_reading('stats', P, y);
verifyEqual(tc, C.rowsum_dev, 1, 'AbsTol', 1e-12);
verifyEqual(tc, C.ece, 0.5 * 0.1 + 0.5 * 0, 'AbsTol', 1e-12);
verifyEqual(tc, C.top(15, 1:3), [4 1 1], 'AbsTol', 1e-12);
verifyEqual(tc, C.acc, 0.75, 'AbsTol', 1e-12);
verifyError(tc, @() calibration_reading('stats', P, [y(1:7); 4]), 'calibration_reading:labels');
end

function test_nonfinite_rows_dropped(tc)
% A row with a NaN probability or label is dropped and counted, never binned.
P = [repmat([0.9 0.1], 10, 1); NaN 0.5; 0.5 0.5]; y = [ones(9, 1); 2; 1; NaN];
C = calibration_reading('stats', P, y);
verifyEqual(tc, C.n_dropped, 2); verifyEqual(tc, C.n, 10);
verifyEqual(tc, C.ece, 0, 'AbsTol', 1e-12);
verifyEqual(tc, calibration_reading('stats', [0.2 0.8; 1 0], [2; 1]).top([4 15], 1), [0; 1]);   % integer bins: 0.8 in bin 13, 1 in bin 15
end

function test_bins_count(tc)
rs = RandStream('mt19937ar', 'Seed', 3);
P = rand(rs, 500, 4); y = randi(rs, 4, 500, 1);
C = calibration_reading('stats', P, y, 10);
verifyEqual(tc, size(C.top, 1), 10);
verifyEqual(tc, sum(C.top(:, 1)), 500);
verifyEqual(tc, arrayfun(@(c) sum(c.table(:, 1)), C.cls), 500 * ones(1, 4));
verifyGreaterThanOrEqual(tc, C.ece, 0); verifyLessThanOrEqual(tc, C.ece, 1);
end

function test_labels_only_tree(tc)
% A tree whose prediction file holds labels only, and a fusion file: the first is listed as such,
% the second is read; the reading is never overwritten.
d = tempname; mkdir(fullfile(d, 'results')); mkdir(fullfile(d, 'data'));
cl = onCleanup(@() rmdir(d, 's')); %#ok<NASGU>
pred = struct('y_true', [1; 2], 'y_pred', [1; 1], 'y_fused', [1; 2]); %#ok<NASGU>
save(fullfile(d, 'results', 'detector_predictions_fresh9.mat'), 'pred');
val_probs_oof = [0.8 0.2; 0.3 0.7; 0.6 0.4]; val_target = [1; 2; 2]; %#ok<NASGU>
save(fullfile(d, 'data', 'fusion.mat'), 'val_probs_oof', 'val_target');
tag = sprintf('unit_%d', randi(1e9));
od = fullfile(tc.TestData.root, 'results', 'calibration', tag);
c2 = onCleanup(@() rm_if(od)); %#ok<NASGU>
calibration_reading(d, tag);
txt = fileread(fullfile(od, 'calibration_reading.txt'));
verifyTrue(tc, contains(txt, 'labels only'));
verifyTrue(tc, contains(txt, 'data/fusion.mat'));
S = load(fullfile(od, 'calibration_reading.mat'));
verifyEqual(tc, numel(S.R), 1);
verifyEqual(tc, S.R(1).C.brier, calibration_reading('stats', [0.8 0.2; 0.3 0.7; 0.6 0.4], [1; 2; 2]).brier);
verifyError(tc, @() calibration_reading(d, tag), 'calibration_reading:exists');
end

function rm_if(d)
if isfolder(d), rmdir(d, 's'); end
end

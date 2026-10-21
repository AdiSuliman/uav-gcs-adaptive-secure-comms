function C = core_cnn_config()
%CORE_CNN_CONFIG  The protocol of the three-state spectrogram CNN (train_core_cnn.m,
%   docs/core_cnn_protocol.md), fixed before any run.
%   groups, names  the dataset class and the name of each state
%   epochs         schedules trained; the one with the best validation macro-F1 is kept
%   seed           rng seed before each schedule
%   NS             window grid [cycles] (select_fusion.m's); K folds by sub-run, fold_seed
%   n_boot, boot_seed  bootstrap over test sub-runs (eval_detector.m's)
%   thr            the lecturer's thresholds (fractions)
%   files          model, marker, protocol, test set and the hybrid's fourth-set reading
C.groups = {'none', 'tone_jamming', 'jamming'};
C.names = {'clean', 'narrowband jamming', 'wideband jamming'};
C.epochs = [30 60];
C.seed = 42;
C.NS = [1 3 5 8 12];
C.K = 5;
C.fold_seed = 61;
C.n_boot = 1000;
C.boot_seed = 7;
C.thr = struct('macro_f1', 0.85, 'recall', 0.85, 'false_alarm', 0.05);
C.model = 'data/core_cnn_model.mat';
C.marker = 'results/core_cnn_read_started.txt';
C.protocol = 'docs/core_cnn_protocol.md';
C.test = 'data/splits_fresh3.mat';
C.test_params = 'data/splits_fresh3_params.mat';
C.hybrid_pred = 'results/detector_predictions_fresh3.mat';
C.hybrid_metrics = 'results/eval_detector_metrics_fresh3.mat';
end

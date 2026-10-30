function S = lb_seeds()
%LB_SEEDS  The random streams of the link-budget completion (train_dqn.m, lb_adopt.m, lb_columns.m):
%   specs, the episodes' onsets and follower delays; frames, the frame-draw seed of the
%   validation sets (+ 100 x set + batch) and of the clean flights (+ 5000 + batch), the same
%   for both settings of a pair; boot, the cluster bootstraps of the adoption rule (one per
%   validation set, then the path-loss family); cols, those of the test columns (one per set, then
%   the family). Distinct from each other and from the streams of the rest of the stage
%   (test_lb.m).
S = struct('specs', 88001, 'frames', 88000, 'boot', [15001 15002 15003 15004 15101], 'cols', [15201 15202 15203 15204 15211]);
end

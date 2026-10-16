function assert_frame1_onsets(p)
%ASSERT_FRAME1_ONSETS  Stops a stage whose parameters do not put every threat on from its
%   run's first frame, as init_params.m writes them: pl_onset_frames and fault_onset_frames
%   [1 1], roll_in_frames []. The pools, the latency runs and the gallery set their own
%   onsets (an episode's onset, a rolling-in flight's event frame), so a params.mat holding
%   another stage's settings (the detector's onsets inside its sub-runs, run_dataset_sweep.m)
%   would move them silently.
%   p  the params struct the stage loaded from params.mat
f = {'pl_onset_frames', 'fault_onset_frames', 'roll_in_frames'};
ok = all(isfield(p, f)) && isequal(p.pl_onset_frames, [1 1]) && isequal(p.fault_onset_frames, [1 1]) ...
    && isempty(p.roll_in_frames);
if ~ok
    error('assert_frame1_onsets:params', ['params.mat does not put every threat on from the first frame ' ...
        '(pl_onset_frames and fault_onset_frames [1 1], roll_in_frames []): run init_params (A0)']);
end
end

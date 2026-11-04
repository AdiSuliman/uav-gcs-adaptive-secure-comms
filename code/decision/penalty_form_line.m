function L = penalty_form_line(Q)
%PENALTY_FORM_LINE  The report line for the form of the false-switch penalty the deployed agent trained under,
%   next to the line that prints the penalty: {} when C2 did not run with the no-threat form's switch
%   (the output is then the earlier one).
%   Q  a struct of what data/trained_dqn.mat holds: dec.fa_form, else seed_summary.selected_fa_form
%   L  a 1x1 cell with the line, or an empty cell
L = {};
f = '';
if isstruct(Q) && isfield(Q, 'dec') && isstruct(Q.dec) && isfield(Q.dec, 'fa_form')
    f = Q.dec.fa_form;
elseif isstruct(Q) && isfield(Q, 'seed_summary') && isstruct(Q.seed_summary) && isfield(Q.seed_summary, 'selected_fa_form')
    f = Q.seed_summary.selected_fa_form;
end
if isempty(f), return; end
if strcmp(f, 'nothreat')
    t = 'the full penalty only on cycles with no threat on the air, the standard one elsewhere';
else
    t = 'the penalty on every change on a healthy link';
end
L = {sprintf('Form of the training false-switch penalty of the selected DQN: %s (%s; fa_form_train.m).', char(f), t)};
end

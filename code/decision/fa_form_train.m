function Kt = fa_form_train(Kt, Kval, form)
%FA_FORM_TRAIN  The form of the false-switch penalty in a training reward Kt (link_env.m).
%   form 'all' (also empty or absent): Kt unchanged, its penalty Kt.FA on every change on a
%        healthy link
%   form 'nothreat': Kt.FA only on the cycles with no threat on the air (the clean flight and
%        the cycles before the onset and after the end), Kval.FA, the standard reward's, on
%        every other cycle: the penalty's excess over the standard reward sits where the
%        clean-flight false-alarm constraint is defined, its Lagrangian (Altman 1999)
%   form a struct: a C2 seed_summary, its selected_fa_form ('all' without the field)
%   Any other value stops. Kval, the reward validation and test read, is never changed.
if nargin < 3, form = 'all'; end
if isstruct(form)
    if isfield(form, 'selected_fa_form'), form = form.selected_fa_form; else, form = 'all'; end
end
if isempty(form), return; end
if ~((ischar(form) || isstring(form)) && any(strcmp(form, {'all', 'nothreat'})))
    error('fa_form_train:value', 'fa_form_train: the penalty form must be ''all'' or ''nothreat''');
end
if strcmp(form, 'all'), return; end
Kt.fa_form = 'nothreat';
Kt.FA_threat = Kval.FA;
end

function R = fusion_reading(tag)
%FUSION_READING  What a detector reading is, by the fusion in data/fusion.mat when it is read.
%   R = fusion_reading(tag)   tag: the reading's suffix ('' the second test set or, without it,
%   the test split; '_split', '_fresh2' the third test set, '_fresh3' the fourth)
%   R.fusion_rev  the fusion's fusion_rev ('' for the old layout or no fusion)
%   R.state       'deployed revision' (fusion_rev_id('enlarged')), 'kept fusion after a no-go'
%                 (fusion_nogo.m), or ''
%   R.sample      'in-sample (fit set of the deployed fusion)' for a reading of the test split,
%                 the second or the third test set with the deployed revision: those sets are
%                 in its fit set (fit_sets.m), so the reading describes, it does not test; ''
%                 otherwise. The fourth set (B3q) was built and read after the fusion's fit.
R = struct('fusion_rev', '', 'state', '', 'sample', '');
fk = 'data/fusion.mat';
if ~isfile(fk), return; end
if ismember('fusion_rev', {whos('-file', fk).name})
    L = load(fk, 'fusion_rev');
    if ischar(L.fusion_rev), R.fusion_rev = L.fusion_rev; end
end
if strcmp(R.fusion_rev, fusion_rev_id('enlarged'))
    R.state = 'deployed revision';
    if ~strcmp(tag, '_fresh3'), R.sample = 'in-sample (fit set of the deployed fusion)'; end
elseif fusion_nogo('check')
    R.state = 'kept fusion after a no-go';
end
end

function sha = dev_d91_code()
%DEV_D91_CODE  The commit of the d91 proof code, printed as 'D91CODE <sha>': D91_SHA.txt at the
%   root of the queue's export of it, else d91_sha.txt, which git archive fills with the
%   exported commit (export-subst). The drivers' copy sits next to that export ('new').
%   'unknown' when neither holds a commit id.
here = fileparts(mfilename('fullpath'));
f = {fullfile(pwd, 'D91_SHA.txt'), fullfile(here, '..', '..', 'D91_SHA.txt'), fullfile(here, '..', 'new', 'D91_SHA.txt'), ...
    fullfile(here, 'd91_sha.txt'), fullfile(here, '..', 'new', 'code', 'dev', 'd91_sha.txt')};
sha = 'unknown';
for k = 1:numel(f)
    if ~isfile(f{k}), continue; end
    s = strtrim(fileread(f{k}));
    if ~isempty(regexp(s, '^[0-9a-f]{7,40}$', 'once')), sha = s; break; end
end
fprintf('D91CODE %s\n', sha);
end

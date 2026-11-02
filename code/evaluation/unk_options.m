function O = unk_options(f)
%UNK_OPTIONS  The switches of D111 and of D116 reading 3 in this checkout's profile.json (f,
%   default 'profile.json'), every one false without the file or the field:
%   O.k2_0  measure_all_kpis.m prints the K2-0 lines beside KPI 2 (k2_0_lines.m; descriptive,
%           never KPI 2)
%   D111's statistic itself has no switch here: it runs wherever data/fusion.mat holds FM.unk
%   (unk_stat.m), which only the OOD run writes (ood_k2_run.m) after its select phase adopts.
if nargin < 1 || isempty(f), f = 'profile.json'; end
O = struct('k2_0', false);
if ~isfile(f), return; end
P = jsondecode(fileread(f));
if ~isstruct(P) || ~isfield(P, 'k2_0'), return; end
v = P.k2_0;
if ~(isscalar(v) && islogical(v)), error('unk_options:value', '%s: k2_0 must be true or false', f); end
O.k2_0 = v;
end

function Us = rr_us(f)
%RR_US  D2c's receiver uncertainty U_s per unit of KPI 8's paired differences (D121 item 3):
%   Us.per (packet error rate, absolute), Us.gput (goodput, bit/s), Us.trec (detection to
%   restored, cycles), read from variable Us of the file f (default results/d2c_us.mat, to be
%   written by D2c in these units). A field the file does not give, or no file, is NaN, which
%   rr_column.m prints as "n/a".
if nargin < 1 || isempty(f), f = fullfile('results', 'd2c_us.mat'); end
Us = struct('per', NaN, 'gput', NaN, 'trec', NaN);
if ~isfile(f), return; end
S = load(f, 'Us');
if ~isfield(S, 'Us') || ~isstruct(S.Us), return; end
for n = fieldnames(Us)'
    if isfield(S.Us, n{1}) && isscalar(S.Us.(n{1})), Us.(n{1}) = double(S.Us.(n{1})); end
end
end

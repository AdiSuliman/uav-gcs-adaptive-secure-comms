function b = clean_ber_ref(ebno, kind)
%CLEAN_BER_REF  Clean-link reference at a given Eb/N0 [dB], log-interpolated from
%   clean_ref of data/policy_pools.mat: the clean link's mean per Eb/N0 over the 300
%   clean validation flights (clean_ref_rebuild.m, at C1c); between C1p and C1c, over
%   the clean cell's train flights. NaN when the pools do not exist yet.
%   kind  'ber'      true BER (evaluation, default)
%         'ber_est'  the receiver's BER estimate on the clean link: the monitor
%                    compares like with like, so the estimator's bias cancels
%         'plr_fec'  CRC packet loss of the clean link with fec_interleave
%   The table is cached; the pools file is checked for a newer version at most
%   every 30 s, so a decision cycle does not wait on the file system.
%   old = clean_ber_ref('interpolant', on)  a griddedInterpolant in place of interp1 (off by
%   default; on only where kpi7_guard.m reads it bit-identical); old: the previous setting.
persistent R stamp checked T gi
if isempty(gi), gi = false; end
if ischar(ebno)
    if ~strcmp(ebno, 'interpolant'), error('clean_ber_ref: unknown command %s', ebno); end
    b = gi; if nargin > 1, gi = logical(kind); end
    return
end
if nargin < 2, kind = 'ber'; end
f = 'data/policy_pools.mat';
if isempty(checked) || toc(checked) > 30
    if isfile(f), d = dir(f); now_stamp = d.datenum; else, now_stamp = NaN; end
    if isempty(stamp) || ~isequaln(stamp, now_stamp)
        R = []; T = struct();
        if isfile(f)
            L = load(f, 'clean_ref'); R = L.clean_ref;
        end
        stamp = now_stamp;
    end
    checked = tic;
end
if isempty(R) || ~isfield(R, kind), b = NaN(size(ebno)); return; end
if ~isfield(T, kind)                                   % the table in the log domain, per kind
    x = R.ebno(:); T.(kind) = struct('x', x, 'ly', log10(max(R.(kind)(:), 1e-7)), 'F', []);
end
t = T.(kind);
q = min(max(ebno, t.x(1) - 4), t.x(end) + 4);
if gi
    if isempty(t.F), t.F = griddedInterpolant(t.x, t.ly, 'linear', 'linear'); T.(kind).F = t.F; end
    b = 10.^reshape(t.F(q(:)), size(q));
else
    b = 10.^interp1(t.x, t.ly, q, 'linear', 'extrap');
end
end

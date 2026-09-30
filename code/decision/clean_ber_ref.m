function b = clean_ber_ref(ebno, kind)
%CLEAN_BER_REF  Clean-link reference at a given Eb/N0 [dB], log-interpolated from
%   the none / no_action cells of data/policy_pools.mat. NaN when the
%   pools do not exist yet.
%   kind  'ber'      true BER (evaluation, default)
%         'ber_est'  the receiver's BER estimate on the clean link: the monitor
%                    compares like with like, so the estimator's bias cancels
%         'plr_fec'  CRC packet loss of the clean link with fec_interleave
%   The table is cached; the pools file is checked for a newer version at most
%   every 30 s, so a decision cycle does not wait on the file system.
persistent R stamp checked
if nargin < 2, kind = 'ber'; end
f = 'data/policy_pools.mat';
if isempty(checked) || toc(checked) > 30
    if isfile(f), d = dir(f); now_stamp = d.datenum; else, now_stamp = NaN; end
    if isempty(stamp) || ~isequaln(stamp, now_stamp)
        R = [];
        if isfile(f)
            L = load(f, 'clean_ref'); R = L.clean_ref;
        end
        stamp = now_stamp;
    end
    checked = tic;
end
if isempty(R) || ~isfield(R, kind), b = NaN(size(ebno)); return; end
x = R.ebno(:); y = R.(kind)(:);
b = 10.^interp1(x, log10(max(y, 1e-7)), min(max(ebno, x(1) - 4), x(end) + 4), 'linear', 'extrap');
end

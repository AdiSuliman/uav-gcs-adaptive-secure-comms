function dev_noise_floor(out, tags, NT)
%DEV_NOISE_FLOOR  The receiver's noise floor: the median eigenvalue of the quiet slot's
%   space-time covariance (st_quiet in build_threat_model.m, taps half a symbol apart)
%   against the thermal level of the run, for NT taps per antenna (default 5 and 9), on
%   the dumped frames (dev_dump.m). Prints the estimate over the thermal level [dB], median
%   and 5-95%, per case and Eb/N0.
if nargin < 1, out = []; end
if nargin < 2 || isempty(tags), tags = {'j16r3d234', 'j30r3d234', 'j16r3d1000', 'j30r9d64', 'j16r9d1000', 'c5d1000'}; end
if nargin < 3 || isempty(NT), NT = [5 9]; end
dev_setup('floor', out, true);
if isempty(out), out = fullfile(tempdir, 'uav_gcs_dev'); end
for t = tags
    S = load(fullfile(out, ['dump_' t{1} '.mat'])); D = S.D; q = S.q;
    rrc = comm.RaisedCosineReceiveFilter('RolloffFactor', q.rolloff, 'FilterSpanInSymbols', q.filter_span, ...
        'InputSamplesPerSymbol', q.sps, 'DecimationFactor', 1);
    g2 = sum(abs(coeffs(rrc).Numerator).^2);
    QN = q.quiet_symbols * q.sps; Q0 = q.filter_span * q.sps + 1; HS = q.sps / 2; NR = size(D(1).u, 2);
    r = nan(numel(D), numel(NT)); e = [D.ebno];
    for i = 1:numel(D)
        if i == 1 || D(i).seed ~= D(i-1).seed || D(i).ebno ~= D(i-1).ebno, reset(rrc); end
        rf = rrc(double(D(i).u));
        if D(i).f == 1, continue; end
        s2 = g2 / q.sps / 10^((D(i).ebno + 10*log10(q.bits_per_symbol) - 10*log10(q.sps)) / 10);   % thermal level after the filter
        for j = 1:numel(NT)
            T0 = (NT(j) - 1) / 2; m = (Q0 + T0*HS : QN - T0*HS)';
            Y = complex(zeros(numel(m), NR * NT(j)));
            for l = 1:NT(j), Y(:, (l-1)*NR + (1:NR)) = rf(m + (l-1-T0)*HS, :); end
            r(i, j) = 10*log10(median(real(eig(Y.' * conj(Y) / numel(m)))) / s2);
        end
    end
    for ev = unique(e)
        k = e == ev & ~isnan(r(:, 1))';
        for j = 1:numel(NT)
            fprintf('%-11s Eb/N0 %2d, %d taps: floor over thermal %+.1f dB [5-95%%: %+.1f %+.1f]\n', t{1}, ev, NT(j), ...
                median(r(k, j)), quantile(r(k, j), 0.05), quantile(r(k, j), 0.95));
        end
    end
end
end

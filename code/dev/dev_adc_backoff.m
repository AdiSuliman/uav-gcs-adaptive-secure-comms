function dev_adc_backoff(out, tags)
%DEV_ADC_BACKOFF  p.adc_backoff_db: the 1 - 1e-4 quantile of the composite's rails over
%   their RMS on the dumped raw frames (dev_dump.m), and the clipped share and SQNR of
%   the 12-bit front end at a full scale 11.8 dB (a Gaussian's quantile) above the rail
%   RMS (adc_frontend.m with the receiver's AGC windows).
if nargin < 1, out = []; end
if nargin < 2 || isempty(tags), tags = {'c2d234', 'c5d1000', 'j16r3d234', 'j30r3d234', 'jt', 'j16k5b'}; end
dev_setup('adc', out, true);
if isempty(out), out = fullfile(tempdir, 'uav_gcs_dev'); end
fprintf('Gaussian rail: 2Q(3.89) = %.2e, 20 log10(3.89) = %.2f dB\n', 2*qfunc(3.89), 20*log10(3.89));
for t = tags
    S = load(fullfile(out, ['dump_' t{1} '.mat'])); D = S.D; q = S.q;
    QN = q.quiet_symbols * q.sps; iq = 1:QN;
    is = QN + q.filter_span/2*q.sps + round(q.timing_max_sym*q.sps) + (1:16*q.sps);
    for e = unique([D.ebno])
        k = find([D.ebno] == e); c = zeros(1, numel(k)); pk = c; sq = c;
        for j = 1:numel(k)
            u = double(D(k(j)).u);
            [y, ~, c(j)] = adc_frontend(u, 12, 11.8, iq, is);
            r = [real(u(:)); imag(u(:))]; pk(j) = 20*log10(quantile(abs(r), 1 - 1e-4) / sqrt(mean(r.^2)));
            sq(j) = 10*log10(sum(abs(u(:)).^2) / sum(abs(y(:) - u(:)).^2));
        end
        fprintf('%-9s %2d dB: rail 1-1e-4 quantile %.2f dB over RMS | clipped share mean %.1e max %.1e | SQNR %.1f dB\n', ...
            t{1}, e, median(pk), mean(c), max(c), median(sq));
    end
end
end

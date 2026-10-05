function dev_dump(tag, out, seeds)
%DEV_DUMP  Received frames of one dev case (dev_cases.m) for the receiver's dev scripts:
%   per frame the raw input of the Rx block on every antenna (the front end off, so the
%   samples are those before the AGC and ADC), the transmitted bits, the receiver's bits
%   and output 6, and output 6 of the same flight without the interferer at 40 dB (the
%   genie arrival and frequency). Saves <out>/dump_<tag>.mat.
%   seeds: optional subset of the case's seeds (a short check).
if nargin < 2, out = []; end
C = dev_cases(); c = C(strcmp(C(:, 1), tag), :);
if isempty(c), error('dev_dump: unknown case %s', tag); end
p0 = dev_setup(tag, out, true);
if nargin < 3 || isempty(seeds), seeds = c{8}; end
q = p0; q.active_threat = c{2}; q.jsr_db = c{3}; q.rx_corr = c{4}; q.rician_k = c{5};
q.tdl = any(c{6} > 0); q.tdl_ds_ns = c{6}; q.rx_combiner = 'mmse'; q.adc_bits = 0;
nfr = 21;
mdl = 'UAV_GCS_Threat_Link';
D = struct('u', {}, 'tx', {}, 'rx', {}, 'sy', {}, 'seed', {}, 'f', {}, 'ebno', {});
evalc('build_threat_model(q)');
for e = c{7}
    set_param([mdl '/AWGN'], 'SNR', num2str(e + 10*log10(q.bits_per_symbol) - 10*log10(q.sps)), 'SignalPower', num2str(1/q.sps));
    for s = seeds
        link_seed(mdl, s, q.fd_max);
        o = sim(mdl, 'StopTime', num2str(nfr * q.frame_duration));
        U = o.get('Rx_IQ'); S = reshape(o.get('Rx_S'), 8, []);
        tx = reshape(double(o.get('tx_bits_out')), q.frame_length, []);
        rx = reshape(double(o.get('rx_bits_out')), q.frame_length, []);
        for f = 1:min([size(U, 3), size(tx, 2), size(rx, 2)])
            D(end+1) = struct('u', single(U(:, :, f)), 'tx', logical(tx(:, f)), 'rx', logical(rx(:, f)), ...
                'sy', S(:, f), 'seed', s, 'f', f, 'ebno', e); %#ok<AGROW>
        end
    end
end
close_system(mdl, 0);
g = q; g.active_threat = 'none'; g.rx_combiner = 'mrc';
evalc('build_threat_model(g)');
set_param([mdl '/AWGN'], 'SNR', '40', 'SignalPower', num2str(1/q.sps));
GS = containers.Map('KeyType', 'double', 'ValueType', 'any');
for s = seeds
    link_seed(mdl, s, q.fd_max);
    o = sim(mdl, 'StopTime', num2str(nfr * q.frame_duration));
    GS(s) = reshape(o.get('Rx_S'), 8, []);
end
close_system(mdl, 0);
for i = 1:numel(D)
    S = GS(D(i).seed); D(i).gsy = S(:, D(i).f);
end
if isempty(out), out = fullfile(tempdir, 'uav_gcs_dev'); end
save(fullfile(out, ['dump_' tag '.mat']), 'D', 'q', '-v7.3');
b = arrayfun(@(x) mean(x.tx ~= x.rx), D);
fprintf('DUMP %s: %d frames, receiver BER %.3e, frames > 0.2: %d\n', tag, numel(D), mean(b), sum(b > 0.2));
end

function dev_fec_flights(set, seeds, out)
%DEV_FEC_FLIGHTS  Dev flights of the coded packets: per frame the uncoded BER, the sync
%   flag, sync coherence and pilot error, and the aligned bits, the reference antenna's IQ
%   and the combiner output for the decoders. Three cases, 20 frames per flight, each
%   flight's geometry drawn as in the pools: a 16 dB jammer under spatial_diversity on the
%   delay line (6, 12 dB), a 30 dB jammer at K 10 dB, its channel spread 234 ns and ours
%   flat, rho 0.3, MMSE (12, 15 dB), the clean link under MRC (0, 3 dB). Dev set A: seeds
%   7201-7260 (thresholds), set B: 7301-7360 (the readings). Saves <out>/dev_<set>.mat.
if nargin < 3, out = []; end
p0 = dev_setup(['fec_' set], out, false);
if isempty(out), out = fullfile(tempdir, 'uav_gcs_dev'); end
mdl = 'UAV_GCS_Threat_Link';
C = {
  % name        threat     jsr  combiner  ebno      tdl_random  ds          rho   intK
  'a_j16_mmse', 'jamming', 16,  'mmse',   [6 12],   true,       [0 0],      NaN,  NaN
  'b_j30_234',  'jamming', 30,  'mmse',   [12 15],  false,      [0 234],    0.3,  10
  'c_clean',    'none',    0,   'mrc',    [0 3],    true,       [0 0],      NaN,  NaN
};
R = struct();
for ci = 1:size(C, 1)
    p = p0; p.active_threat = C{ci, 2}; p.jsr_db = C{ci, 3}; p.rx_combiner = C{ci, 4};
    p.tdl_random = C{ci, 6}; p.tdl_ds_ns = C{ci, 7};
    if isfinite(C{ci, 8}), p.corr_random = false; p.rx_corr = C{ci, 8}; end
    if isfinite(C{ci, 9}), p.int_rician_k = C{ci, 9}; end
    evalc('build_threat_model(p)');
    for eb = C{ci, 5}
        set_param([mdl '/AWGN'], 'SNR', num2str(eb + 10*log10(p.bits_per_symbol) - 10*log10(p.sps)), 'SignalPower', num2str(1/p.sps));
        S = struct('ber', [], 'sf', [], 'pe', [], 'coh', [], 'tx', {{}}, 'rx', {{}}, 'iq', {{}}, 'z', {{}});
        for sd = seeds
            link_seed(mdl, sd, p.fd_max, struct('ebno', eb));
            o = sim(mdl, 'StopTime', num2str(19 * p.frame_duration));
            q = p; q.fec = false;
            F = extract_closed_loop_frames(o, q, 20);
            txb = double(squeeze(o.get('tx_bits_out'))); rxb = double(squeeze(o.get('rx_bits_out')));
            iqa = o.get('Rx_IQ'); [ns, ~, nf] = size(iqa);
            S.ber(end+1, :) = F.ber; S.sf(end+1, :) = F.sync_fail; S.coh(end+1, :) = F.sync_coh;
            S.pe(end+1, :) = F.pilot_err;
            S.tx{end+1} = txb(1:nf*p.frame_length); S.rx{end+1} = rxb(1:nf*p.frame_length);
            S.iq{end+1} = single(reshape(iqa(:, 1, :), ns, nf));
            S.z{end+1} = single(squeeze(o.get('Rx_Z')));
        end
        fprintf('%s %g dB: %d flights, lost frames %d, sync flags %d\n', C{ci, 1}, eb, numel(seeds), ...
            nnz(S.ber(:) > 0.2), nnz(S.sf(:) > 0.5));
        R.(sprintf('%s_%02d', C{ci, 1}, eb)) = S;
    end
    close_system(mdl, 0);
end
R.p = p0;
save(fullfile(out, ['dev_' set '.mat']), 'R', '-v7.3');
end

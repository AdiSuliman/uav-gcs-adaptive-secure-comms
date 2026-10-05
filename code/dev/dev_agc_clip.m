function T = dev_agc_clip(out, seeds, ebno, comb, att)
%DEV_AGC_CLIP  The held AGC gain under gated interferers: per frame the share of the
%   rails the 12-bit front end clips (adc_frontend.m on the raw received frame, the
%   receiver's AGC windows: the quiet slot and the first 16 short-training symbols) and
%   the frame's BER with the front end on and off, on the same flights (the same seeds:
%   the same channel, interferer and noise). Gated threats (noise_burst, sweeping_jammer,
%   benign_interference, reactive_jamming) at the nominal and the largest level, the
%   continuous jammer as the reference; the pools' geometry draws, real receiver, comb
%   the combiner ('mrc', no_action, default; 'mmse', spatial_diversity's); att the front
%   end's fast attack (p.adc_attack_db, default init_params'; Inf: the gain held over the
%   frame). Dev seeds 7401-7415 by default, Eb/N0 12 dB, 20 frames per flight.
if nargin < 1, out = []; end
if nargin < 2 || isempty(seeds), seeds = 7401:7415; end
if nargin < 3 || isempty(ebno), ebno = 12; end
if nargin < 4 || isempty(comb), comb = 'mrc'; end
p0 = dev_setup(['agc_' comb], out, false);
if nargin >= 5 && ~isempty(att), p0.adc_attack_db = att; end
C = {
  'jamming',             'jsr_db',        [16 30]
  'noise_burst',         'jsr_db',        [16 30]
  'sweeping_jammer',     'jsr_db',        [16 30]
  'reactive_jamming',    'jsr_db',        [16 30]
  'benign_interference', 'benign_int_db', [12 30]
};
mdl = 'UAV_GCS_Threat_Link';
QN = p0.quiet_symbols * p0.sps;
is = QN + p0.filter_span/2*p0.sps + round(p0.timing_max_sym*p0.sps) + (1:16*p0.sps);
T = table();
for c = 1:size(C, 1)
    for L = C{c, 3}
        clip = []; act = []; ber = zeros(0, 2);
        for adc = [0 p0.adc_bits]
            p = p0; p.active_threat = C{c, 1}; p.(C{c, 2}) = L; p.adc_bits = adc; p.rx_combiner = comb;
            evalc('build_threat_model(p)');
            set_param([mdl '/AWGN'], 'SNR', num2str(ebno + 10*log10(p.bits_per_symbol) - 10*log10(p.sps)), ...
                'SignalPower', num2str(1/p.sps));
            b = [];
            for sd = seeds
                link_seed(mdl, sd, p.fd_max, struct('ebno', ebno));
                o = sim(mdl, 'StopTime', num2str(19 * p.frame_duration));
                q = p; q.fec = false;
                F = extract_closed_loop_frames(o, q, 20);
                b = [b, F.ber(2:end)]; %#ok<AGROW>
                if adc == 0
                    U = o.get('Rx_IQ');
                    for f = 2:size(U, 3)
                        [~, ~, cf] = adc_frontend(double(U(:, :, f)), p0.adc_bits, p0.adc_backoff_db, 1:QN, is, p0.adc_attack_db);
                        clip(end+1) = cf; %#ok<AGROW>
                    end
                    act = [act, F.act(2:end)]; %#ok<AGROW>
                end
            end
            ber(1:numel(b), 1 + (adc > 0)) = b(:);
            close_system(mdl, 0);
        end
        T = [T; table(string(C{c, 1}), L, numel(clip), mean(clip), mean(clip > 1e-3), mean(clip > 1e-2), max(clip), ...
            mean(act), mean(ber(:, 1)), mean(ber(:, 2)), mean(ber(:, 1) > 0.2), mean(ber(:, 2) > 0.2), ...
            'VariableNames', {'threat', 'level_db', 'frames', 'clip_mean', 'frames_clip_1e3', 'frames_clip_1e2', ...
            'clip_max', 'on_air', 'ber_off', 'ber_on', 'lost_off', 'lost_on'})]; %#ok<AGROW>
        fprintf('%s %g dB done\n', C{c, 1}, L);
    end
end
format short g
disp(T);
end

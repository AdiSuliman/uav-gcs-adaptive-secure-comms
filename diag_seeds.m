function diag_seeds()
%% DIAG_SEEDS - Which random source of the threat link is not reproducible (D41)
% Same seed, three runs: (a) build+sim, (b) sim again without rebuilding,
% (c) rebuild+sim. Compares the bit stream, the transmitted IQ, the received IQ
% without noise (channel only) and with noise (channel + AWGN).
warning('off', 'Simulink:cgxe:LeakedJITEngine');
S = load('params.mat'); p = S.params;
p.quiet_build = true; p.active_threat = 'none'; p.seed = 2001;
mdl = 'UAV_GCS_Threat_Link';
snr_on = 4 + 10*log10(p.bits_per_symbol) - 10*log10(p.sps);

fprintf('\n--- Seed-related block parameters after build ---\n');
params = p; save('params.mat', 'params');
evalc('build_threat_model');
blks = {'AWGN', 'BitSource'};
for b = 1:numel(blks)
    dp = fieldnames(get_param([mdl '/' blks{b}], 'DialogParameters'));
    k = dp(contains(lower(dp), {'seed', 'random', 'stream'}));
    for j = 1:numel(k)
        fprintf('  %-10s %-20s = %s\n', blks{b}, k{j}, num2str(get_param([mdl '/' blks{b}], k{j})));
    end
end

R = cell(3, 2);
for n = 1:2                                  % n = 1: no noise, n = 2: Eb/N0 4 dB
    snr = [200 snr_on]; 
    params = p; save('params.mat', 'params'); evalc('build_threat_model');
    set_param([mdl '/AWGN'], 'SNR', num2str(snr(n)), 'SignalPower', num2str(1/p.sps));
    R{1,n} = grab(sim(mdl, 'StopTime', '0.005'));
    R{2,n} = grab(sim(mdl, 'StopTime', '0.005'));
    evalc('build_threat_model');
    set_param([mdl '/AWGN'], 'SNR', num2str(snr(n)), 'SignalPower', num2str(1/p.sps));
    R{3,n} = grab(sim(mdl, 'StopTime', '0.005'));
end

fprintf('\n--- Identical to run (a)?   b = sim again, c = rebuild ---\n');
fprintf('%-28s %6s %6s\n', 'signal', 'b', 'c');
row('bits (bit source)',            @(r) r.bits, R(:,1));
row('Tx IQ',                        @(r) r.tx,   R(:,1));
row('Rx IQ, no noise (channel)',    @(r) r.rx,   R(:,1));
row('Rx IQ, 4 dB (channel+AWGN)',   @(r) r.rx,   R(:,2));
row('Rx bits, 4 dB',                @(r) r.rb,   R(:,2));
params = S.params; save('params.mat', 'params');
end

function r = grab(out)
r.bits = squeeze(out.get('tx_bits_out'));
r.tx   = squeeze(out.get('Tx_IQ'));
r.rx   = squeeze(out.get('Rx_IQ'));
r.rb   = squeeze(out.get('rx_bits_out'));
end

function row(name, f, C)
a = f(C{1});
s = cell(1, 2);
for i = 2:3
    b = f(C{i});
    if isequal(size(a), size(b)) && max(abs(a(:) - b(:))) == 0, s{i-1} = 'yes'; else, s{i-1} = 'NO'; end
end
fprintf('%-28s %6s %6s\n', name, s{1}, s{2});
end

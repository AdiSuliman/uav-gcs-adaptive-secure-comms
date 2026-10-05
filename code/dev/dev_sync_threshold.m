function dev_sync_threshold(out, tags)
%DEV_SYNC_THRESHOLD  p.sync_coh_min: the largest threshold on a 0.05 grid that flags at
%   most 1% of the correctly synchronized dev frames (frequency within 500 Hz of the genie
%   run without the interferer). The receiver with the front end on and no flag
%   (sync_coh_min 0) runs over the dumped frames (dev_dump.m of every case of
%   dev_cases.m but j30r3d0, which runs the flat receiver); the first frame of each flight
%   (the receive filter's start) is left out. Prints the coherence quantiles per case and
%   the flagged shares per threshold.
if nargin < 1, out = []; end
C = dev_cases();
if nargin < 2 || isempty(tags), tags = C(~strcmp(C(:, 1), 'j30r3d1000'), 1)'; end
p0 = dev_setup('sync', out, true);
if isempty(out), out = fullfile(tempdir, 'uav_gcs_dev'); end
S = load(fullfile(out, ['dump_' tags{1} '.mat']), 'q'); q = S.q;
q.adc_bits = p0.adc_bits; q.adc_backoff_db = p0.adc_backoff_db; q.sync_coh_min = 0;
dev_rx_script(q, 'rx_dl', out);
q.tdl = false; dev_rx_script(q, 'rx_flat', out);
A = []; F = []; B = [];
for t = tags
    nm = 'rx_dl'; if strcmp(t{1}, 'j30r3d0'), nm = 'rx_flat'; end
    r = dev_eval_rx(t{1}, nm, out); k = r.f > 1;
    a = r.sy(6, k); fail = abs(r.ferr(k)) > 500; b = r.ber(k);
    fprintf('%-11s coherence of the synchronized frames [1 5 50]%%: %s | off > 500 Hz: %d | lost (BER > 0.2): %d, median coherence %.3f\n', ...
        t{1}, mat2str(quantile(a(~fail), [0.01 0.05 0.5]), 3), sum(fail), sum(b > 0.2), median(a(b > 0.2)));
    A = [A a]; F = [F fail]; B = [B b]; %#ok<AGROW>
end
grid = 0.05:0.05:0.95;
fg = arrayfun(@(t) mean(A(~F) < t), grid);
tau = grid(find(fg <= 0.01, 1, 'last'));
for t = grid(grid >= 0.3 & grid <= 0.7)
    fprintf('tau %.2f: synchronized flagged %.2f%% | off flagged %d/%d | lost flagged %d/%d\n', t, 100*mean(A(~F) < t), ...
        sum(A(F == 1) < t), sum(F), sum(A(B > 0.2) < t), sum(B > 0.2));
end
fprintf('sync_coh_min = %.2f (%d frames)\n', tau, numel(A));
end

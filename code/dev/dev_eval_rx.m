function R = dev_eval_rx(tag, name, out)
%DEV_EVAL_RX  Runs <out>/rxlib/<name>.m (dev_rx_script.m) over the frames of
%   <out>/dump_<tag>.mat, flight by flight (the receive filter's state starts empty per
%   flight, as in the block). R per frame: BER, output 6 (sy), its arrival and frequency
%   errors against the genie (derr [samples], ferr [Hz]), the dump's receiver BER
%   (base_ber), frame index f and Eb/N0.
if nargin < 3 || isempty(out), out = fullfile(tempdir, 'uav_gcs_dev'); end
addpath(fullfile(out, 'rxlib'));
S = load(fullfile(out, ['dump_' tag '.mat'])); D = S.D;
fn = str2func(name);
n = numel(D); ber = zeros(1, n); sy = zeros(8, n);
for i = 1:n
    if i == 1 || D(i).seed ~= D(i-1).seed || D(i).ebno ~= D(i-1).ebno
        clear(name);
    end
    tx = double(D(i).tx);
    [b, ~, ~, ~, ~, s] = fn(double(D(i).u), tx);
    ber(i) = mean(double(b(:)) ~= tx);
    sy(1:numel(s), i) = s;
end
gs = [D.gsy];
R = struct('ber', ber, 'sy', sy, 'ebno', [D.ebno], 'derr', sy(1, :) - gs(1, :), 'ferr', sy(2, :) - gs(2, :), ...
    'base_ber', arrayfun(@(x) mean(x.tx ~= x.rx), D), 'f', [D.f]);
end

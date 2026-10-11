function h = benign_hit_share(p, n, nf)
%BENIGN_HIT_SHARE  Expected share of the frames the WLAN interferer counts in.
%   h = benign_hit_share(p, n, nf): a frame counts when at least 10% of it carries a packet
%   (threat_active.m). The packet schedule of the threat block (build_threat_model.m): per
%   flight an occupancy uniform in p.benign_occ, packets log-uniform in p.benign_pkt_s,
%   idle gaps gamma with the shape p.benign_idle_shape and the mean the occupancy sets,
%   on the channel clock with the frames p.cycle_s apart. n runs of nf frames (default
%   3000 x 20, the dataset's sub-runs) from a fixed stream.
if nargin < 2 || isempty(n), n = 3000; end
if nargin < 3 || isempty(nf), nf = 20; end
rs = RandStream('mt19937ar', 'Seed', 2033);
fs = p.symbol_rate * p.sps; tf = p.samples_per_frame / fs;
d = p.benign_pkt_s; md = (d(2) - d(1)) / log(d(2) / d(1)); k = p.benign_idle_shape;
tend = (nf - 1) * p.cycle_s + tf;
lab = 0;
for r = 1:n
    occ = p.benign_occ(1) + diff(p.benign_occ) * rand(rs);
    on = rand(rs) < occ;                    % the state from t = 0
    t = 0; iv = zeros(0, 2);
    while t < tend
        if on
            dur = exp(log(d(1)) + log(d(2) / d(1)) * rand(rs));
            iv(end+1, :) = [t, t + dur]; t = t + dur; %#ok<AGROW>
        else
            t = t + gamma_ms(rs, k) * md * (1 - occ) / occ / k;
        end
        on = ~on;
    end
    for f = 1:nf
        a = (f - 1) * p.cycle_s; b = a + tf;
        s = sum(max(0, min(iv(:, 2), b) - max(iv(:, 1), a))) / tf;
        lab = lab + (s >= 0.1);
    end
end
h = lab / (n * nf);
end

function g = gamma_ms(rs, k)
% Gamma(k, 1) by Marsaglia-Tsang (shape k + 1 and U^(1/k) when k < 1), as the threat block.
a = k + (k < 1); dd = a - 1/3; c = 1 / sqrt(9 * dd);
g = 0;
while g == 0
    x = randn(rs); v = (1 + c * x)^3;
    if v > 0 && log(rand(rs)) < 0.5 * x^2 + dd - dd * v + dd * log(v)
        g = dd * v;
    end
end
if k < 1, g = g * rand(rs)^(1 / k); end
end

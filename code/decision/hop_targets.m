function c = hop_targets(rule, home, n, rs, B)
%HOP_TARGETS  Channels of an episode's successive hops (the bandwidth study, band_plan.m).
%   c = hop_targets(rule, home, n, rs, B)  the n channels (indices into B.f_mhz) the first n
%       hops move to from the home channel, each from the one before:
%       'H1'  pseudo-random, uniform over the plan's channels at least 6 MHz from the channel
%             in use (IEEE 802.11-2007 14.6.8: a pseudo-random pattern using the band
%             uniformly, minimum hop 6 MHz in North America and Europe; ETSI EN 300 328's
%             uniform use), drawn from rs, the episode's 'hop' stream (seed_stream.m), so the
%             GCS and the UAV share it and every policy flies the same sequence
%       'H3'  26 MHz (13 channels) toward the plan's middle channel, up from the middle
%             itself (802.11: channels 25 MHz or more apart operate without interference), so a
%             repeat hop past the middle comes back across it
%       'H4'  4 MHz (2 channels) toward the middle, on in that direction and reflected at the
%             plan's edges
%   home = hop_targets('home', can, [], rs)  the home channel: uniform over the channels
%       where can (1 x channels, logical) is true
if strcmp(rule, 'home')
    k = find(home);
    assert(~isempty(k), 'hop_targets:home', 'hop_targets: no channel to start on');
    c = k(randi(rs, numel(k)));
    return
end
nC = numel(B.f_mhz); mid = B.centre;
gap = ceil(6 / B.spacing - 1e-9);                      % channels in 6 MHz
c = zeros(1, n); j = home;
dir = 1; if j > mid, dir = -1; end
for h = 1:n
    switch rule
        case 'H1'
            k = find(abs((1:nC) - j) >= gap);
            j = k(randi(rs, numel(k)));
        case 'H3'
            if j > mid, j = j - 13; else, j = j + 13; end
        case 'H4'
            if j + 2 * dir < 1 || j + 2 * dir > nC, dir = -dir; end
            j = j + 2 * dir;
        otherwise
            error('hop_targets:rule', 'hop_targets: unknown hop rule %s', rule);
    end
    c(h) = j;
end
end

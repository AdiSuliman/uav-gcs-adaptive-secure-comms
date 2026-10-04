function specs = policy_episodes(cells, nS, rr, reps, follow, unk, NE, T, rs, fdelay)
%POLICY_EPISODES  Episode batches over every (cell, Eb/N0, geometry) (link_env.m specs).
%   specs = policy_episodes(cells, nS, rr, reps, follow, unk, NE, T, rs)
%   specs = policy_episodes(..., fdelay)
%   Every (cell, Eb/N0 index 1:nS, geometry rr: indices into PP.runs{split}) `reps`
%   times, packed into batches of NE; the last batch is padded cyclically and keeps
%   its n_valid episodes (policy_run_set.m drops the rest). Onset uniform in cycles
%   3-10 and follower delay uniform in fdelay (cycles a follower needs to re-acquire
%   the channel, default [2 5]), both from the stream rs; follow: follower jammer,
%   unk: detector output withheld after the onset.
if nargin < 10, fdelay = [2 5]; end
[c, s, r] = ndgrid(cells, 1:nS, rr);
c = repmat(c(:)', 1, reps); s = repmat(s(:)', 1, reps); r = repmat(r(:)', 1, reps);
n = numel(c); nb = ceil(n / NE); pad = nb * NE - n;
k_ = mod(0:n + pad - 1, n) + 1; c = c(k_); s = s(k_); r = r(k_);             % cyclic padding of the last batch
specs = cell(1, nb);
for b = 1:nb
    i = (b-1)*NE + (1:NE);
    specs{b} = struct('scn', c(i), 's', s(i), 'r', r(i), 'onset', randi(rs, [3 10], 1, NE), ...
        'follow', repmat(follow, 1, NE), 'fdelay', randi(rs, fdelay, 1, NE), 'unk', repmat(unk, 1, NE), 'T', T);
end
specs{end}.n_valid = NE - pad;
end

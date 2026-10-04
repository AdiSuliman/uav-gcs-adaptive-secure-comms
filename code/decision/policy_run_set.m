function R = policy_run_set(kind, PP, K, specs, split, ag, opt, seed0)
%POLICY_RUN_SET  Every batch of one episode set under one policy (rollout_policy.m).
%   R = policy_run_set(kind, PP, K, specs, split, ag, opt, seed0): batch b runs with
%   the frame-draw seed seed0 + b, so every policy sees the same draws; the padding of
%   the last batch (n_valid, policy_episodes.m) is dropped. Per episode, besides the
%   rollout outputs: scn, s, threat (not the clean link), the scenario of the spec
%   (onset, follow, fdelay, unk, delay: signalling delay of a change in cycles, comb:
%   a jammer on every channel we can use), split,
%   geom (flight geometry, the bootstrap cluster within a split) and speed (UAV speed
%   the geometry was flown at, km/h).
R = [];
D = decision_config().switch_delay;                     % link_env.m's delay when the spec sets none
for b = 1:numel(specs)
    sp = specs{b};
    Rb = rollout_policy(kind, PP, K, sp, split, ag, opt, seed0 + b);
    Rb.scn = sp.scn; Rb.s = sp.s;
    Rb.threat = ~strcmp(PP.scen(Rb.scn), 'none');
    Rb.onset = sp.onset; Rb.follow = sp.follow; Rb.fdelay = sp.fdelay; Rb.unk = sp.unk;
    if isfield(sp, 'delay') && ~isempty(sp.delay), Rb.delay = sp.delay * ones(size(sp.scn));
    else, Rb.delay = D * ones(size(sp.scn)); end
    Rb.comb = false(size(sp.scn)); if isfield(sp, 'comb') && ~isempty(sp.comb), Rb.comb = sp.comb; end
    Rb.split = split * ones(size(sp.scn));
    Rb = rmfield(Rb, 'cfg_trace');
    if isfield(sp, 'n_valid')
        f = fieldnames(Rb);
        for j = 1:numel(f), Rb.(f{j}) = Rb.(f{j})(:, 1:sp.n_valid); end
    end
    if isempty(R), R = Rb; else, R = cat_struct(R, Rb); end
end
R.geom = 1000 * R.s + R.r;                              % flight geometry (bootstrap cluster)
R.speed = PP.speed{split}(sub2ind(size(PP.speed{split}), R.s, R.r));   % speed the geometry was flown at
end

function R = cat_struct(R, Rb)
f = fieldnames(R);
for i = 1:numel(f), R.(f{i}) = [R.(f{i}), Rb.(f{i})]; end
end

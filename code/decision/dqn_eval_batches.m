function R = dqn_eval_batches(kind, PP, K, specs, agent, opt, seed0, split)
%DQN_EVAL_BATCHES  Roll a policy out over batches of episodes (rollout_policy.m) and concatenate the results.
R = [];
for b = 1:numel(specs)
    Rb = rollout_policy(kind, PP, K, specs{b}, split, agent, opt, seed0 + b);
    Rb = rmfield(Rb, 'cfg_trace');
    Rb.threat = ~strcmp(PP.scen(specs{b}.scn), 'none');
    if isempty(R), R = Rb; else, R = structfun_cat(R, Rb); end
end
end

function R = structfun_cat(R, Rb)
f = fieldnames(R);
for i = 1:numel(f), R.(f{i}) = [R.(f{i}), Rb.(f{i})]; end
end

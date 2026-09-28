function tab = policy_table(PP, K)
%POLICY_TABLE  Class -> configuration lookup tuned on the train pools (D45, D59).
%   The strongest static mapping from the detected class: for each threat, the
%   configuration with the best mean reward per cycle (quality minus running cost)
%   over every severity, Eb/N0 and train geometry; 'none' -> no_action; 'unknown'
%   -> the best configuration averaged over all single threats. Baseline for the
%   'table' policy of policy_decide.m, so the DQN is compared with the best
%   class-based mapping the data allows and not only with expert rules.
%   tab: table (1 x numel(PP.classes) action index), table_unknown, names
nA = numel(PP.actions); nR = K.nR(1);
score = nan(numel(PP.classes), nA);
for k = 1:numel(PP.classes)
    cells = find(strcmp(PP.scen, PP.classes{k}));
    if isempty(cells) || strcmp(PP.classes{k}, 'none'), continue; end
    Q = K.q(cells, :, :, 1, 1:nR);
    Q = reshape(permute(Q, [3 1 2 4 5]), nA, []);
    score(k, :) = mean(Q, 2, 'omitnan')' - K.cost;
end
tab.table = K.na * ones(1, numel(PP.classes));
for k = 1:numel(PP.classes)
    if all(isnan(score(k, :))), continue; end
    [~, tab.table(k)] = max(score(k, :));
end
[~, tab.table_unknown] = max(mean(score, 1, 'omitnan'));
tab.names = PP.actions(tab.table);
end

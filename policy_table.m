function tab = policy_table(PP, K)
%POLICY_TABLE  Class -> configuration lookup tuned on the train pools (D45).
%   The strongest static mapping from the detected class: for each threat, the
%   configuration with the best mean reward per cycle (quality minus running
%   cost) over every Eb/N0 and train sub-run; 'none' -> no_action; 'unknown' ->
%   the best configuration averaged over all single threats. Baseline for the
%   'table' policy of policy_decide.m, so the DQN is compared with the best
%   class-based mapping the data allows and not only with expert rules.
%   tab: table (1 x numel(PP.classes) action index), table_unknown, names
nA = numel(PP.actions); nR = K.nR(1);
score = nan(numel(PP.scen), nA);
for sc = 1:numel(PP.singles)
    Q = K.q(sc, :, :, 1, 1:nR);                              % 1 x nS x nA x 1 x nR
    Q = reshape(permute(Q, [3 2 5 1 4]), nA, []);
    score(sc, :) = mean(Q, 2, 'omitnan')' - K.cost;
end
tab.table = K.na * ones(1, numel(PP.classes));
for k = 1:numel(PP.classes)
    sc = find(strcmp(PP.scen, PP.classes{k}), 1);
    if ~isempty(sc) && sc > 1
        [~, tab.table(k)] = max(score(sc, :));
    end
end
[~, tab.table_unknown] = max(mean(score(2:numel(PP.singles), :), 1, 'omitnan'));
tab.names = PP.actions(tab.table);
end

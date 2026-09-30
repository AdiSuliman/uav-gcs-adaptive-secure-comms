function spec = dqn_episode_spec(H, PP, K, rs, split)
%DQN_EPISODE_SPEC  A batch of H.NE random training or validation episodes.
%   Episodes on the cells present in the split: single threats (every severity),
%   the clean link and the combined threats; a cell whose pools are emptied
%   (experiment_combo_generalization.m) is left out. Onset, follower jammer, its
%   re-acquisition delay (C.fdelay) and withheld detector output drawn per episode.
avail = find(~cellfun(@isempty, PP.pools(:, 1, K.na, split))');
w = ones(1, numel(avail));
nV = numel(PP.sev_names);
w(strcmp(PP.scen(avail), 'none')) = nV;             % the clean link as often as a threat at all severities
w(strcmp(PP.scen(avail), 'benign_interference')) = 1.5;
w(ismember(PP.scen(avail), PP.combos)) = 1.5;
cw = cumsum(w) / sum(w);
NE = H.NE; C = decision_config();
scn = avail(arrayfun(@(u) find(u <= cw, 1), rand(rs, 1, NE)));
spec = struct('scn', scn, 's', randi(rs, numel(PP.ebno), 1, NE), 'onset', randi(rs, [3 10], 1, NE), ...
    'follow', K.followable(scn) & rand(rs, 1, NE) < H.p_follow, 'fdelay', randi(rs, C.fdelay, 1, NE), ...
    'unk', ~strcmp(PP.scen(scn), 'none') & rand(rs, 1, NE) < H.p_unknown, 'T', H.T);
end

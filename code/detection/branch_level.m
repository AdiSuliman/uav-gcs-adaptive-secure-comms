function [y, names] = branch_level(c)
%BRANCH_LEVEL  The class names read at the branch level: an antenna fault and airframe
%   shadowing both lose one receive branch (the same physics on the antennas, the same
%   answer of the rule, rule_based_policy.m), so they read as 'one_branch_lost'.
%   y = branch_level(c): c a cell array of class names (or categorical); y the names at
%   the branch level. [~, names] = branch_level(classes): the classes at that level.
c = cellstr(string(c));
y = c;
y(ismember(c, {'antenna_fault', 'airframe_shadowing'})) = {'one_branch_lost'};
names = reshape(unique(y, 'stable'), [], 1);
end

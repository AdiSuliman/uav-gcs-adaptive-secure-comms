function own = pool_seed_owner(fam, block)
%POOL_SEED_OWNER  The set that owns geometry family fam of seed block block (pool_seed.m), ''
%   for a pair no set uses: 'pools' family 1 (every block: the pools, the clean-link
%   geometries 1-100, the earlier test readings), 'check' family 2 (block 10), 'clean' families
%   3 and 5 (blocks 4 and 15), 'core_bw' family 6 (blocks 5, 7, 14, 16, 18, 19), 'fresh'
%   families 7, 8 and 9 (block 15: P1R's fresh clean test set, docs/p1r_protocol.md; block 18:
%   its smoke build), 'fresh_threat' family 4 (block 14: the fresh profile-3 test set of the weak-point
%   fixes, fresh_set_layout.m; block 18: its smoke build), 'w19' families 7, 8 and 9 of block 17 (that
%   set's clean flights, clean_set_layout.m; block 16: its smoke build). test_core's and test_weak19's
%   seed tests list the same pairs.
U = {1, 1:19, 'pools'; 2, 10, 'check'; 3, [4 15], 'clean'; 5, [4 15], 'clean'; ...
    6, [5 7 14 16 18 19], 'core_bw'; 7, [15 18], 'fresh'; 8, [15 18], 'fresh'; 9, [15 18], 'fresh'; ...
    4, [14 18], 'fresh_threat'; 7, [16 17], 'w19'; 8, [16 17], 'w19'; 9, [16 17], 'w19'};
own = '';
for i = 1:size(U, 1)
    if U{i, 1} == fam && ismember(block, U{i, 2}), own = U{i, 3}; return; end
end
end

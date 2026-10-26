function own = pool_seed_owner(fam, block)
%POOL_SEED_OWNER  The set that owns geometry family fam of seed block block (pool_seed.m), ''
%   for a pair no set uses: 'pools' family 1 (every block: the pools, the clean-link
%   geometries 1-100, the earlier test readings), 'check' family 2 (block 10), 'clean' families
%   3 and 5 (blocks 4 and 15), 'core_bw' family 6 (blocks 5, 7, 14, 16, 18, 19), 'fresh'
%   families 7, 8 and 9 (block 15: P1R's fresh clean test set, docs/p1r_protocol.md).
%   test_core's seed tests list the same pairs.
U = {1, 1:19, 'pools'; 2, 10, 'check'; 3, [4 15], 'clean'; 5, [4 15], 'clean'; ...
    6, [5 7 14 16 18 19], 'core_bw'; 7, 15, 'fresh'; 8, 15, 'fresh'; 9, 15, 'fresh'};
own = '';
for i = 1:size(U, 1)
    if U{i, 1} == fam && ismember(block, U{i, 2}), own = U{i, 3}; return; end
end
end

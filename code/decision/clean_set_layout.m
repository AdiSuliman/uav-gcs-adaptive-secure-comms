function [SP, FAMS, f_out] = clean_set_layout(set, smoke)
%CLEAN_SET_LAYOUT  Seed block, geometry families and output of a clean-link set of
%   build_clean_test_pools.m (CLEAN_SET):
%   'test'   block 15, families 1, 3, 5 -> data/clean_test_pools.mat
%   'val'    block 4,  families 1, 3, 5 -> data/clean_val_pools.mat
%   'fresh'  block 15, families 7, 8, 9 -> data/clean_fresh_pools.mat: P1R's KPI 6 set
%            (docs/p1r_protocol.md), seeds no earlier set flew; with smoke true (SMOKE) block
%            18, the smoke's own, so the smoke never flies the fresh set's flights
%   'fresh' stops when any of its (family, block) pairs belongs to another set (pool_seed_owner.m).
if nargin < 2, smoke = false; end
switch set
    case 'test',  SP = 15; FAMS = [1 3 5]; f_out = 'data/clean_test_pools.mat';
    case 'val',   SP = 4;  FAMS = [1 3 5]; f_out = 'data/clean_val_pools.mat';
    case 'fresh', SP = 15; FAMS = [7 8 9]; f_out = 'data/clean_fresh_pools.mat';
        if smoke, SP = 18; end
    otherwise, error('clean_set_layout:set', 'build_clean_test_pools: CLEAN_SET must be ''test'', ''val'' or ''fresh''');
end
if strcmp(set, 'fresh')
    own = arrayfun(@(f) pool_seed_owner(f, SP), FAMS, 'UniformOutput', false);
    if ~all(strcmp(own, 'fresh'))
        error('clean_set_layout:reuse', 'clean_set_layout: the fresh set''s families %s of block %d are not its own (%s)', ...
            mat2str(FAMS), SP, strjoin(own, ', '));
    end
end
end

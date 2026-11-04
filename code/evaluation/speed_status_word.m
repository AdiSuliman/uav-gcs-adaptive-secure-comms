function s = speed_status_word(st, SU)
%SPEED_STATUS_WORD  KPI 7's status row with the union line's qualifier (measure_all_kpis.m): a MET
%   whose union word is 'MET (not committed)' (the point within the target, the upper bound above it,
%   speed_reading.m) reads 'MET (not committed)'; any other status is unchanged.
s = st;
if strcmp(st, 'MET') && isstruct(SU) && isfield(SU, 'word_union') && strcmp(SU.word_union, 'MET (not committed)')
    s = 'MET (not committed)';
end
end

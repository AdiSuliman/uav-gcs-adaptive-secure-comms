function [rec_pct, ratio] = recovery_vs_clean(ber_before, ber_after, ber_clean)
%RECOVERY_VS_CLEAN  Link recovery relative to the no-attack link (proposal KPI #2).
%
%   rec_pct = 100 * (ber_before - ber_after) / (ber_before - ber_clean)
%     Share of the attack-induced BER excess that the countermeasure removed.
%     Capped at 100 (ber_after can dip below the reference through noise or a
%     diversity gain). NaN when the reference is missing or the attack caused
%     no measurable degradation (ber_before within 10% of ber_clean).
%
%   ratio = ber_after / ber_clean
%     Survivability-map criterion: <= 2 recoverable, <= 5 marginal.

rec_pct = NaN;
ratio   = NaN;
if ~isfinite(ber_clean) || ber_clean <= 0
    return;
end

ratio = ber_after / ber_clean;

gap = ber_before - ber_clean;
if gap <= 0.1 * ber_clean
    return;
end
rec_pct = min(100, 100 * (ber_before - ber_after) / gap);
end
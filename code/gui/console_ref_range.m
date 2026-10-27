function r = console_ref_range()
%CONSOLE_REF_RANGE  Range [lo hi] of the clean link's mean BER at Eb/N0 9 dB (clean_ref.ber,
%   clean_ber_ref(9, 'ber')) that a clean-link reference may hold: the range clean_ref_rebuild.m
%   pre-registered for that value (docs/clean_ref_protocol.md section 4, 3e-4 to 6e-3), the same
%   check as core_bw_rules('clean_ref'). The monitor's estimate (ber_est) is only required to
%   be finite. The exporter and the console's start stop on a reference outside the range: the
%   table is stale or wrong, and the link monitor would misjudge a clean or degraded link.
r = [3e-4 6e-3];
end

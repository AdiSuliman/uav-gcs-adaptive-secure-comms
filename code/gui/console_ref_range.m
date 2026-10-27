function r = console_ref_range()
%CONSOLE_REF_RANGE  Range [lo hi] of the clean link's BER estimate at Eb/N0 9 dB that a
%   clean-link reference may hold, as clean_ref_rebuild.m expects it (docs/clean_ref_protocol.md,
%   pre-registered 3e-4 to 6e-3). The exporter and the console's start stop on a reference
%   outside it: the link monitor would alarm on a clean link (too low) or miss a degraded
%   one (too high).
r = [3e-4 6e-3];
end

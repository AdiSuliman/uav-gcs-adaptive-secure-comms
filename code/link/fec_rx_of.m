function rx = fec_rx_of(X)
%FEC_RX_OF  The coded link's decoder that frames, pools or params X were made with.
%   rx = fec_rx_of(X): X.fec_rx when it is a decoder struct with mode 'jsi' (per-symbol
%   jammer state information and residual erasures, fec_packets.m), else the D78 erasure
%   rules, struct('mode', 'd78'): pools and params without the field (profile 1's) were
%   decoded with them.
rx = struct('mode', 'd78');
if isstruct(X) && isfield(X, 'fec_rx') && isstruct(X.fec_rx) && isfield(X.fec_rx, 'mode') ...
        && strcmp(X.fec_rx.mode, 'jsi')
    rx = X.fec_rx;
end
end

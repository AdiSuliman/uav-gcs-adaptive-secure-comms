function p = fec_rx_on(p, R)
%FEC_RX_ON  Params p with the decoder R (fec_rx_config.m): p.fec_rx = R for the JSI decoder;
%   the D78 rules and an unstated decoder leave p as it is, so its keys and identity
%   (pool_checkpoint.m, pool_configs.m) stay those of the frames already built with them.
if ~isempty(R) && isstruct(R) && strcmp(R.mode, 'jsi'), p.fec_rx = R; end
end

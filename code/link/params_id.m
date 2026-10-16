function id = params_id(p)
%PARAMS_ID  Identity of the link model's parameters: an MD5 of their JSON text.
%   Only init_params writes params.mat in a run (the stages build their models in memory;
%   the GUI and two diagnostics still write it and restore it), so the file's time can move
%   while its content does not; results tied to the link model (validate_phy.m) carry this
%   identity instead.
md = java.security.MessageDigest.getInstance('MD5');
h = typecast(md.digest(uint8(jsonencode(p))), 'uint8');
id = lower(reshape(dec2hex(h, 2)', 1, []));
end

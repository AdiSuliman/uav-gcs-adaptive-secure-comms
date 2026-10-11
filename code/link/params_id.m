function id = params_id(p)
%PARAMS_ID  Identity of the link model's parameters: an MD5 of their JSON text.
%   Stages that rebuild the model write params.mat for each threat and restore it, so
%   the file's time moves while its content does not; results tied to the link model
%   (validate_phy.m) carry this identity instead.
md = java.security.MessageDigest.getInstance('MD5');
h = typecast(md.digest(uint8(jsonencode(p))), 'uint8');
id = lower(reshape(dec2hex(h, 2)', 1, []));
end

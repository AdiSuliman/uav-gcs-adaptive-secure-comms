function b = clean_ber_ref(ebno)
%CLEAN_BER_REF  Clean-link BER at a given Eb/N0 [dB], log-interpolated from the
%   measured none/no_action cells of data/policy_pools.mat (D44). NaN when the
%   pools do not exist yet.
persistent x y
if isempty(x)
    x = []; y = [];
    if isfile('data/policy_pools.mat')
        L = load('data/policy_pools.mat', 'clean_ref');
        x = L.clean_ref.ebno(:); y = L.clean_ref.ber(:);
    end
end
if isempty(x), b = NaN(size(ebno)); return; end
b = 10.^interp1(x, log10(max(y, 1e-7)), min(max(ebno, x(1) - 4), x(end) + 4), 'linear', 'extrap');
end

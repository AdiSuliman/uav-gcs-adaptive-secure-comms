function b = clean_ber_ref(ebno)
%CLEAN_BER_REF  Measured clean-link BER at a given Eb/N0 (log-interpolated).
%   Source: data/survivability_boundary.mat (5-repeat baseline), otherwise
%   data/trained_dqn.mat. Returns NaN when neither file is available.
persistent snr ber
if isempty(snr)
    snr = []; ber = [];
    if isfile('data/survivability_boundary.mat')
        L = load('data/survivability_boundary.mat', 'SNR_points', 'ber_clean');
        snr = L.SNR_points; ber = L.ber_clean;
    elseif isfile('data/trained_dqn.mat')
        L = load('data/trained_dqn.mat', 'SNR_LIST', 'clean');
        if isfield(L, 'clean'), snr = L.SNR_LIST; ber = L.clean; end
    end
end
if isempty(snr)
    b = NaN;
    return;
end
b = 10.^interp1(snr(:), log10(max(ber(:), 1e-9)), ebno, 'linear', 'extrap');
end

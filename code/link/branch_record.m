function B = branch_record(F, nr)
%BRANCH_RECORD  Per-frame record of every antenna's channel estimates: the input of the
%   fusion's branch-coherence cues (window_cues.m). Receiver measurements only.
%   B = branch_record(F)   F from extract_closed_loop_frames.m; B is (9 nr) x frames:
%     gain      the antenna's mean channel gain [dB] (F.gain_ant)
%     hq_re/im  its frame-mean complex channel estimate (the data blocks' channels, F.hq)
%     hq_nv     the noise power of that mean: the residual power over the symbols averaged
%     g0_re/im  its channel at the frame's line-of-sight lag l0: the whole-symbol lag that
%               holds the most power summed over the antennas (F.cir)
%     g0_nv     the noise power of that lag's LS estimate
%     p0, pr    its noise-debiased power at l0 and at every other lag together
%   names = branch_record('names', nr)
if ischar(F)
    b = {'gain', 'hq_re', 'hq_im', 'hq_nv', 'g0_re', 'g0_im', 'g0_nv', 'p0', 'pr'};
    B = cell(1, 9 * nr);
    for k = 1:9, for a = 1:nr, B{(k - 1) * nr + a} = sprintf('%s_%d', b{k}, a); end, end
    return;
end
[nr, nf] = size(F.gain_ant);
B = nan(9 * nr, nf);
blk = @(k) (k - 1) * nr + (1:nr);
B(blk(1), :) = F.gain_ant;
if isfield(F, 'hq') && ~isempty(F.hq)
    B(blk(2), :) = real(F.hq); B(blk(3), :) = imag(F.hq);
    B(blk(4), :) = F.rq / (32 * F.hq_nb);
end
if isfield(F, 'cir') && ~isempty(F.cir)
    for f = 1:min(nf, size(F.cir, 3))
        g = F.cir(:, :, f);
        if any(~isfinite(g(:))), continue; end
        P = max(abs(g).^2 - F.cir_nv(:, f) * F.cir_d(:, f).', 0);
        [~, l0] = max(sum(P, 1));
        B(blk(5), f) = real(g(:, l0)); B(blk(6), f) = imag(g(:, l0));
        B(blk(7), f) = F.cir_nv(:, f) * F.cir_d(l0, f);
        B(blk(8), f) = P(:, l0); B(blk(9), f) = sum(P, 2) - P(:, l0);
    end
end
end

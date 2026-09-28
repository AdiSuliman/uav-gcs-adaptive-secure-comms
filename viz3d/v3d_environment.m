function env = v3d_environment(world, L, seed, prefix)
%V3D_ENVIRONMENT  Countryside around the GCS for the Unreal 3D view (D57).
%   env = v3d_environment(world, L, seed, prefix)   prefix makes actor names unique per arena
%
%   Purely scenic and procedural (seeded): a patchwork of fields with dirt tracks,
%   tree lines and groves, a dirt road to the GCS and a ring of hills on the
%   horizon, merged into a few vertex-coloured meshes. The stock EmptyGrass
%   ground covers x > 0 only; the underlay and the hills cover the rest.
if nargin < 3, seed = 7; end
if nargin < 4, prefix = ''; end
rs = RandStream('mt19937ar', 'Seed', seed);
S = 1000;                                   % half-size of the farmland square [m]

[V, F, C] = underlay(L, S);
env.base = addMesh(world, [prefix 'EnvBase'], V, F, C);
[V, F, C, parcels] = fields(L, S, rs);
env.fields = addMesh(world, [prefix 'EnvFields'], V, F, C);
[V, F, C] = road(L, S);
env.road = addMesh(world, [prefix 'EnvRoad'], V, F, C);
[V, F, C] = hills(L, S, rs);
env.hills = addMesh(world, [prefix 'EnvHills'], V, F, C);

T = treeSpots(L, S, parcels, rs);
nChunk = 90;
for c = 1:ceil(size(T, 1) / nChunk)
    idx = (c - 1) * nChunk + 1:min(c * nChunk, size(T, 1));
    [V, F, C, N] = trees(T(idx, :), rs);
    env.trees{c} = addMesh(world, sprintf('%sEnvTrees%d', prefix, c), V, F, C, N);
end
env.nTrees = size(T, 1);
end

%% ===================== Ground =====================
function [V, F, C] = underlay(L, S)
V = [L.G(1:2) + 1.45 * S * [-1 -1; 1 -1; 1 1; -1 1], 0.02 * ones(4, 1)];
F = [0 1 2; 0 2 3];
C = repmat([0.15 0.16 0.08], 4, 1);
end

function [V, F, C, P] = fields(L, S, rs)
% Farmland turned by L.farm_rot: columns of parcels with their own row edges, a
% 5 m dirt track between parcels, and crop rows as alternating strips. P holds
% the parcel rectangles in the farmland frame (relative to the GCS).
pal = [0.10 0.20 0.04; 0.14 0.26 0.05; 0.18 0.30 0.07; 0.08 0.16 0.04; ...
       0.42 0.33 0.10; 0.50 0.40 0.16; 0.22 0.14 0.07; 0.28 0.19 0.10];
w = [3 3 2 2 1.5 1.2 1.2 1]; w = w / sum(w);
Rm = rot2(L.farm_rot);
xs = cumEdges(-1.3 * S, 1.3 * S, 70, 200, rs);
V = zeros(0, 3); F = zeros(0, 3); C = zeros(0, 3); P = zeros(0, 4);
gap = 2.5;
for i = 1:numel(xs) - 1
    ys = cumEdges(-1.3 * S, 1.3 * S, 60, 220, rs);
    for j = 1:numel(ys) - 1
        x0 = xs(i) + gap; x1 = xs(i + 1) - gap; y0 = ys(j) + gap; y1 = ys(j + 1) - gap;
        if abs((x0 + x1) / 2) < 25 && abs((y0 + y1) / 2) < 25, continue; end   % GCS clearing
        k = find(rand(rs) <= cumsum(w), 1);
        base = pal(k, :) .* (0.88 + 0.24 * rand(rs, 1, 3));
        alongX = (x1 - x0) > (y1 - y0);
        nS = max(4, round(max(x1 - x0, y1 - y0) / 9));
        t = linspace(0, 1, nS + 1);
        for m = 1:nS
            if alongX, q = [x0 + (x1 - x0) * t(m), x0 + (x1 - x0) * t(m + 1), y0, y1];
            else,      q = [x0, x1, y0 + (y1 - y0) * t(m), y0 + (y1 - y0) * t(m + 1)];
            end
            loc = [q(1) q(3); q(2) q(3); q(2) q(4); q(1) q(4)];
            n0 = size(V, 1);
            V = [V; loc * Rm' + L.G(1:2), 0.06 * ones(4, 1)]; %#ok<AGROW>
            F = [F; n0 + [0 1 2; 0 2 3]]; %#ok<AGROW>
            C = [C; repmat(base * (1 + 0.035 * (-1) ^ m), 4, 1) .* (0.97 + 0.06 * rand(rs, 4, 1))]; %#ok<AGROW>
        end
        P(end + 1, :) = [x0 x1 y0 y1]; %#ok<AGROW>
    end
end
end

function R = rot2(a)
R = [cos(a) -sin(a); sin(a) cos(a)];
end

function e = cumEdges(a, b, lo, hi, rs)
e = a;
while e(end) < b
    e(end + 1) = e(end) + lo + (hi - lo) * rand(rs); %#ok<AGROW>
end
e(end) = b;
end

function [V, F, C] = road(L, S)
% Dirt road from the GCS to the edge of the farmland, gently winding.
t = linspace(0, 1, 60)';
P = L.G(1:2) + [-(S - 20) * t, 35 * sin(3 * pi * t) .* t];
d = [diff(P); P(end, :) - P(end - 1, :)];
n = [-d(:, 2), d(:, 1)] ./ vecnorm(d, 2, 2);
V = [P + 3 * n, 0.09 * ones(60, 1); P - 3 * n, 0.09 * ones(60, 1)];
k = (0:58)';
F = [k, k + 60, k + 1; k + 1, k + 60, k + 61];
C = repmat([0.30 0.24 0.15], 120, 1);
end

function [V, F, C] = hills(L, S, rs)
% Annulus of hills around the farmland, rising outward; colour by height.
r = [linspace(S * 0.92, S * 1.8, 16), linspace(S * 1.9, S * 5, 20)];
th = linspace(0, 2 * pi, 241); th(end) = [];
[R, TH] = meshgrid(r, th);
k = 3:14;
a = rand(rs, 1, numel(k)) ./ k; ph = 2 * pi * rand(rs, 1, numel(k));
nth = sum(a .* sin(TH(:) * k + ph), 2); nth = (nth - min(nth)) / (max(nth) - min(nth));
nr = 0.5 + 0.5 * sin(R(:) / 260 + 6 * nth);
s = min(max((R(:) - 1.15 * S) / (2.6 * S), 0), 1); s = s .^ 2 .* (3 - 2 * s);
H = 0.03 + 190 * s .* (0.25 + 0.75 * nth .^ 1.5) .* (0.7 + 0.3 * nr);
V = [L.G(1) + R(:) .* cos(TH(:)), L.G(2) + R(:) .* sin(TH(:)), H];
nT = numel(th); nRr = numel(r);
F = zeros(0, 3);
for i = 1:nRr - 1
    for j = 1:nT
        j2 = mod(j, nT) + 1;
        a1 = (i - 1) * nT + j - 1; b1 = (i - 1) * nT + j2 - 1;
        a2 = i * nT + j - 1;       b2 = i * nT + j2 - 1;
        F = [F; a1 a2 b2; a1 b2 b1]; %#ok<AGROW>
    end
end
% Column-major meshgrid: vertex (j, i) is at index (i - 1) * nT + j
h = H / 190;
green = [0.10 0.18 0.05]; olive = [0.22 0.24 0.10]; rock = [0.30 0.27 0.20];
C = (h < 0.5) .* (green + (olive - green) .* (h / 0.5)) + (h >= 0.5) .* (olive + (rock - olive) .* ((h - 0.5) / 0.5));
C = C .* (0.9 + 0.2 * rand(rs, size(C, 1), 1));
end

%% ===================== Trees =====================
function T = treeSpots(L, S, P, rs)
% Tree lines along some parcel edges and a few groves; [x y height kind].
T = zeros(0, 4);
for p = 1:size(P, 1)
    if rand(rs) < 0.15
        e = randi(rs, 4);
        switch e
            case 1, a = [P(p, 1) P(p, 3)]; b = [P(p, 2) P(p, 3)];
            case 2, a = [P(p, 1) P(p, 4)]; b = [P(p, 2) P(p, 4)];
            case 3, a = [P(p, 1) P(p, 3)]; b = [P(p, 1) P(p, 4)];
            otherwise, a = [P(p, 2) P(p, 3)]; b = [P(p, 2) P(p, 4)];
        end
        n = max(2, round(norm(b - a) / 13));
        t = linspace(0, 1, n)';
        xy = (a + t .* (b - a) + 2 * randn(rs, n, 2)) * rot2(L.farm_rot)' + L.G(1:2);
        T = [T; xy, 7 + 5 * rand(rs, n, 1), ones(n, 1)]; %#ok<AGROW>
    end
end
for g = 1:9
    c = L.G(1:2) + (S * 0.8) * (2 * rand(rs, 1, 2) - 1);
    if norm(c - L.G(1:2)) < 160, continue; end
    n = 14 + randi(rs, 16);
    xy = c + 38 * randn(rs, n, 2);
    kind = 1 + (rand(rs, n, 1) < 0.45);
    T = [T; xy, 8 + 7 * rand(rs, n, 1), kind]; %#ok<AGROW>
end
T = T(vecnorm(T(:, 1:2) - L.G(1:2), 2, 2) > 45, :);    % keep the GCS clear
end

function [V, F, C, N] = trees(T, rs)
% Low-poly trees, flat shaded: hexagonal trunk and a broadleaf (faceted ball)
% or conifer (cone) crown; every triangle owns its vertices and an outward normal.
[bv, bf] = ball();
M = struct('V', zeros(0, 3), 'F', zeros(0, 3), 'C', zeros(0, 3), 'N', zeros(0, 3));
for i = 1:size(T, 1)
    p = [T(i, 1:2) 0]; h = T(i, 3); kind = T(i, 4);
    M = appendTris(M, cylTris(0.18 * h / 8 + 0.12, 0.38 * h, 6) + p, [0.18 0.12 0.07], 0.08, rs, @(c) [p(1:2) c(3)]);
    if kind == 1
        ctr = p + [0 0 0.66 * h];
        cr = bv .* [0.36 * h, 0.36 * h, 0.42 * h] .* (0.9 + 0.2 * rand(rs, size(bv, 1), 1)) + ctr;
        M = appendTris(M, cr(reshape(bf', [], 1), :), [0.08 0.17 0.04] .* (0.8 + 0.4 * rand(rs)), 0.14, rs, @(c) ctr);
    else
        M = appendTris(M, coneTris(0.3 * h, 0.85 * h, 8) + p + [0 0 0.22 * h], [0.04 0.11 0.04] .* (0.8 + 0.4 * rand(rs)), ...
            0.14, rs, @(c) [p(1:2) c(3) - 0.5]);
    end
end
V = M.V; F = M.F; C = M.C; N = M.N;
end

function M = appendTris(M, tris, col, jit, rs, ref)
% tris: stacked triangles (3n x 3); ref(centroid) gives a point inside the solid.
n = size(tris, 1) / 3;
nrm = zeros(3 * n, 3);
for k = 1:n
    t = tris(3 * k - 2:3 * k, :);
    q = cross(t(2, :) - t(1, :), t(3, :) - t(1, :)); q = q / max(norm(q), 1e-9);
    c = mean(t, 1);
    if dot(q, c - ref(c)) < 0, q = -q; end
    nrm(3 * k - 2:3 * k, :) = repmat(q, 3, 1);
end
n0 = size(M.V, 1);
M.V = [M.V; tris];
M.N = [M.N; nrm];
M.F = [M.F; n0 + reshape(0:3 * n - 1, 3, []).'];
M.C = [M.C; kron(col .* (1 - jit + 2 * jit * rand(rs, n, 1)), ones(3, 1))];
end

function t = cylTris(r, h, n)
a = 2 * pi * (0:n) / n;
t = zeros(0, 3);
for i = 1:n
    p1 = [r * cos(a(i)) r * sin(a(i))]; p2 = [r * cos(a(i + 1)) r * sin(a(i + 1))];
    t = [t; p1 0; p2 0; p2 h; p1 0; p2 h; p1 h]; %#ok<AGROW>
end
end

function t = coneTris(r, h, n)
a = 2 * pi * (0:n) / n;
t = zeros(0, 3);
for i = 1:n
    t = [t; r * cos(a(i)) r * sin(a(i)) 0; r * cos(a(i + 1)) r * sin(a(i + 1)) 0; 0 0 h; ...
            r * cos(a(i + 1)) r * sin(a(i + 1)) 0; r * cos(a(i)) r * sin(a(i)) 0; 0 0 0]; %#ok<AGROW>
end
end

function [v, f] = ball()
% Icosahedron subdivided once (80 faces), unit radius.
p = (1 + sqrt(5)) / 2;
v = [-1 p 0; 1 p 0; -1 -p 0; 1 -p 0; 0 -1 p; 0 1 p; 0 -1 -p; 0 1 -p; p 0 -1; p 0 1; -p 0 -1; -p 0 1];
v = v ./ vecnorm(v, 2, 2);
f = [1 12 6; 1 6 2; 1 2 8; 1 8 11; 1 11 12; 2 6 10; 6 12 5; 12 11 3; 11 8 7; 8 2 9; ...
     4 10 5; 4 5 3; 4 3 7; 4 7 9; 4 9 10; 5 10 6; 3 5 12; 7 3 11; 9 7 8; 10 9 2];
f2 = zeros(0, 3);
for i = 1:size(f, 1)
    a = f(i, 1); b = f(i, 2); c = f(i, 3);
    v(end + 1, :) = (v(a, :) + v(b, :)) / 2; ab = size(v, 1); %#ok<AGROW>
    v(end + 1, :) = (v(b, :) + v(c, :)) / 2; bc = size(v, 1); %#ok<AGROW>
    v(end + 1, :) = (v(c, :) + v(a, :)) / 2; ca = size(v, 1); %#ok<AGROW>
    f2 = [f2; a ab ca; b bc ab; c ca bc; ab bc ca]; %#ok<AGROW>
end
v = v ./ vecnorm(v, 2, 2);
f = f2;
end

%% ===================== Mesh helper =====================
function a = addMesh(world, name, V, F, C, N)
% Vertex-coloured static mesh. Without N, normals are averaged over faces and
% turned upward (ground and hills).
if nargin < 6
    N = zeros(size(V));
    for i = 1:size(F, 1)
        idx = F(i, :) + 1;
        q = cross(V(idx(2), :) - V(idx(1), :), V(idx(3), :) - V(idx(1), :));
        if q(3) < 0, q = -q; end
        N(idx, :) = N(idx, :) + q;
    end
    N = N ./ max(vecnorm(N, 2, 2), 1e-9);
end
a = sim3d.Actor(ActorName=name);
createMesh(a, V, N, F, zeros(size(V, 1), 2), min(max(C, 0), 1));
a.VertexBlend = 1; a.TwoSided = true; a.Metallic = 0; a.Shininess = 0.05; a.Specular = 0.1;
add(world, a);
end

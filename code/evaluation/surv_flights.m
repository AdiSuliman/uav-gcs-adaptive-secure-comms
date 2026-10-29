function g = surv_flights(t, nr, v)
%SURV_FLIGHTS  The flights of every cell of survivability map entry t under surv_v2
%   (map_survivability_boundary.m, pool_job.m 'surv'): seeds 900000 + 1000 t + (1:nr), run ids
%   1:nr, speed v [km/h]. They depend on neither the level nor the Eb/N0, so two cells of an
%   entry differ only in the level or the noise (common random numbers, as the
%   configurations of a cell share their flights). Disjoint from the one-flight map's seeds
%   900000 + 1000 t + 10 li + s (li >= 1) for nr <= 10.
if nr < 1 || nr > 10 || nr ~= round(nr), error('surv_flights:nr', 'nr must be an integer in 1-10'); end
g = struct('seed', 900000 + 1000 * t + (1:nr), 'speed', v * ones(1, nr), 'run', 1:nr);
end

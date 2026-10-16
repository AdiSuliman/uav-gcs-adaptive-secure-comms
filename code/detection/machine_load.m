function L = machine_load()
%MACHINE_LOAD  The machine's load at a timing (ood_latency.m): the CPU load averaged over
%   the processors [%] and the number of MATLAB sessions running (this one included; on
%   Windows the session's process, not its launcher), so a timing taken beside another run
%   is known as such. NaN when the system does not report it.
L = struct('time', datestr(now, 'yyyy-mm-dd HH:MM:SS'), 'cpu_pct', NaN, 'n_matlab', NaN, ...
    'n_cpu', feature('numcores'));
try
    if ispc
        [st, out] = system(['powershell -NoProfile -Command "(Get-CimInstance Win32_Processor | ' ...
            'Measure-Object -Property LoadPercentage -Average).Average; @(Get-Process -Name MATLAB ' ...
            '-ErrorAction SilentlyContinue | Where-Object { $_.Path -like ''*win64*'' }).Count"']);
        v = str2double(strsplit(strtrim(out)));
        if st == 0 && numel(v) == 2, L.cpu_pct = v(1); L.n_matlab = v(2); end
    else
        [st, out] = system('cat /proc/loadavg');
        if st == 0, v = sscanf(out, '%f', 1); L.cpu_pct = 100 * v / L.n_cpu; end
        [st, out] = system('pgrep -c MATLAB');
        if st == 0, L.n_matlab = str2double(strtrim(out)); end
    end
catch
end
end

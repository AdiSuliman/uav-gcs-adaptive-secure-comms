function s = console_fmt(x, spec)
%CONSOLE_FMT  sprintf(spec, x) for a finite scalar, 'N/A' otherwise: the console never shows NaN or Inf.
if isscalar(x) && isnumeric(x) && isfinite(x)
    s = sprintf(spec, x);
else
    s = 'N/A';
end
end

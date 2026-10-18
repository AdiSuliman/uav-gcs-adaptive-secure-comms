param([string]$sha)
$cmd = '"C:\Program Files\Git\bin\bash.exe" -lc "bash ''/c/Users/Adi Suliman/uav-gcs-logs/v7_d86_launch.sh'' ' + $sha + ' resume >> ''/c/Users/Adi Suliman/uav-gcs-logs/v7_d86_launch.log'' 2>&1"'
$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine=$cmd; CurrentDirectory='C:\Users\Adi Suliman\uav-gcs-logs'}
"resume launcher PID $($r.ProcessId) rc $($r.ReturnValue)"

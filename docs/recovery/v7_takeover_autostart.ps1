# Starts the takeover after a logon (scheduled task "uav-gcs takeover autostart", trigger: Adi's logon + 2 min).
# The command is the approved relaunch command (p3_deploy_prep.md 3.5, Adi 2.11 item 4), unchanged. A takeover whose main bash still runs refuses the
# start ("not started") and changes nothing, so a logon while it runs is harmless.
# Each start is logged in v7_takeover_autostart.log.
$log = 'C:\Users\Adi Suliman\uav-gcs-logs\v7_takeover_autostart.log'
$si = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ShowWindow=[uint16]0}
$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine='"C:\Program Files\Git\bin\bash.exe" -lc "V7T_RERUN_NEED_GB=''55'' V7T_ALLOW_PIDS=''43428 43972'' bash ''/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_takeover.sh'' 24172 49732 >> ''/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_takeover.log'' 2>&1"'; CurrentDirectory='C:\Users\Adi Suliman\uav-gcs-logs'; ProcessStartupInformation=$si}
$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
Add-Content -Path $log -Value ("{0} autostart: ReturnValue {1}, PID {2}, boot {3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $r.ReturnValue, $r.ProcessId, $boot)

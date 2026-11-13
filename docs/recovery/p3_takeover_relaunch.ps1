# The approved takeover relaunch (p3_deploy_prep.md 3.5; Adi 2.11.2026 item 4), verbatim.
# Run only after p3_recovery_check.sh passes and no takeover runs (the takeover refuses a second
# start anyway). Prints the new process's PID and ReturnValue (0 = started).
$si = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ShowWindow=[uint16]0}
Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine='"C:\Program Files\Git\bin\bash.exe" -lc "V7T_RERUN_NEED_GB=''55'' V7T_ALLOW_PIDS=''43428 43972'' bash ''/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_takeover.sh'' 24172 49732 >> ''/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_takeover.log'' 2>&1"'; CurrentDirectory='C:\Users\Adi Suliman\uav-gcs-logs'; ProcessStartupInformation=$si} | Select-Object ProcessId, ReturnValue | Format-List

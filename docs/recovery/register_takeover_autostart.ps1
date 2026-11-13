# One-time registration of the scheduled task "uav-gcs takeover autostart" (run by Adi once).
# At Adi's logon + 2 min it runs v7_takeover_autostart.ps1, which starts the takeover with the approved
# command. A takeover that already runs refuses the second start, so a normal logon is harmless.
# The task only starts the takeover; it changes no file of the project. Remove it with:
#   Unregister-ScheduledTask -TaskName 'uav-gcs takeover autostart' -Confirm:$false
$name = 'uav-gcs takeover autostart'
$user = "$env:USERDOMAIN\$env:USERNAME"
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Users\Adi Suliman\uav-gcs-logs\v7_takeover_autostart.ps1"'
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
$trigger.Delay = 'PT2M'
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Settings $settings -Principal $principal `
    -Description 'Starts the uav-gcs takeover 2 min after logon (approved relaunch command). A running takeover refuses a second start.' -Force | Out-Null
$t = Get-ScheduledTask -TaskName $name
"{0}: state {1}, trigger at logon of {2}, delay {3}" -f $t.TaskName, $t.State, $user, $t.Triggers[0].Delay

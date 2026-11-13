# Recovery after an unexpected stop

The procedure is in `C:\Users\Adi Suliman\uav-gcs-adaptive-secure-comms\RECOVERY_AFTER_SHUTDOWN.md`, the file Adi points Claude to after the computer shuts down. `docs/recovery/` holds versioned copies of that file and of the scripts it runs (`p3_recovery_check.sh`, `p3_takeover_relaunch.ps1`, `p3_recovery_expect.txt`). The working copies are the project-folder file and `uav-gcs-logs`.

Nothing restarts the chain by itself after a reboot. On 13.11.2026 Adi chose not to register a logon task: Claude relaunches the chain when Adi points it to the file.

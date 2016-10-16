function Get-Uptime {
  <#
    .SYNOPSIS
        Gets current system uptime.
    .NOTES
        typedef _SYSTEM_TIMEOFDAY_INFORMATION {
            LARGE_INTEGER BootTime;      // +0x00
            LARGE_INTEGER CurrentTime;   // +0x08
            LARGE_INTEGER TimeZoneBias;  // +0x10
            ULONG         TimeZoneId;    // +0x18
            ULONG         Reserved;      // +0x1c
            ULONGLONG     BootTimeBias;  // +0x20
            ULONGLONG     SleepTimeBias; // +0x28
        } SYSTEM_TIMEOFDAY_INFORMATION, *PSYSTEM_TIMEOFDAY_INFORMATION;
        
        SystemTimeOfDayInformation = 3
  #>
  try {
    # sizeof(SYSTEM_TIMEOFDAY_INFORMATION) = 48
    $sti = [Runtime.InteropServices.Marshal]::AllocHGlobal(48)
    
    if ([Regex].Assembly.GetType(
      'Microsoft.Win32.NativeMethods'
    ).GetMethod(
      'NtQuerySystemInformation'
    ).Invoke($null, @(3, $sti, 48, $null)) -ne 0) {
      throw New-Object InvalidOPerationException(
        'Could not retrieve system uptime.'
      )
    }
    
    [TimeSpan]::FromMilliseconds((
      [Runtime.InteropServices.Marshal]::ReadInt64($sti, 8) -
      [Runtime.InteropServices.Marshal]::ReadInt64($sti)
    ) / 10000)
  }
  catch { $_.Exception }
  finally {
    if ($sti) { [Runtime.InteropServices.Marshal]::FreeHGlobal($sti) }
  }
}

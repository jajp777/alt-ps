function Get-FileCache {
  <#
    .SYNOPSIS
        Shows basic data about system cache.
    .NOTES
        Author: greg zakharov
  #>
  begin {
    Set-Variable ($$ = [Regex].Assembly.GetType(
      'Microsoft.Win32.NativeMethods'
    ).GetMethod('NtQuerySystemInformation')).Name $$

    $page = 4096 # page size
  }
  process {
    try {
      $sfi = [Runtime.InteropServices.Marshal]::AllocHGlobal(36)

      if ($NtQuerySystemInformation.Invoke(
        $null, @(21, $sfi, 36, $null)
      ) -ne 0) {
        throw New-Object InvalidOperationException(
          'Could not retrieve system file cache information.'
        )
      }

      New-Object PSObject -Property @{
        CurrentSize = [Runtime.InteropServices.Marshal]::ReadInt32($sfi)
        PeakSize    = [Runtime.InteropServices.Marshal]::ReadInt32($sfi, 0x04)
        MinimumWS   = [Runtime.InteropServices.Marshal]::ReadInt32($sfi, 0x0c)
        MaximumWS   = [Runtime.InteropServices.Marshal]::ReadInt32($sfi, 0x10)
      } | Select-Object @{
        N='CurrentSize(KB)';E={$_.CurrentSize / 1Kb}
      }, @{N='PeakSize(KB)';E={$_.PeakSize / 1Kb}}, @{
        N='MinimumWS(KB)';E={$_.MinimumWS * $page / 1Kb}
      }, @{N='MaximumWS(KB)';E={$_.MaximumWS * $page / 1Kb}} | Format-List
    }
    catch { Write-Verbose $_ }
    finally {
      if ($sfi) { [Runtime.InteropServices.Marshal]::FreeHGlobal($sfi) }
    }
  }
  end {}
}

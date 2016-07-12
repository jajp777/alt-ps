function Get-FileCache {
  <#
    .SYNOPSIS
        Shows basic data about system cache.
  #>
  begin {
    Set-Variable ($$ = [Regex].Assembly.GetType(
      'Microsoft.Win32.NativeMethods'
    ).GetMethod('NtQuerySystemInformation')).Name $$
    
    $SysInfo = @{
      Basic = @(0, 44)
      FileCache = @(21, 36)
    }
    
    if (($ta = [PSObject].Assembly.GetType(
      'System.Management.Automation.TypeAccelerators'
    ))::Get.Keys -notcontains 'Marshal') {
      $ta::Add('Marshal', [Runtime.InteropServices.Marshal])
    }
    
    function private:Get-PageSize {
      try {
        $ptr = [Marshal]::AllocHGlobal($SysInfo.Basic[1])
        
        if ($NtQuerySystemInformation.Invoke($null, @(
          $SysInfo.Basic[0], $ptr, $SysInfo.Basic[1], 0
        )) -eq 0) {
          [Marshal]::ReadInt32($ptr, 8)
        }
      }
      finally {
        if ($ptr) { [Marshal]::FreeHGlobal($ptr) }
      }
    }
  }
  process {
    $psz = Get-PageSize
    
    try {
      $ptr = [Marshal]::AllocHGlobal($SysInfo.FileCache[1])
      
      if ($NtQuerySystemInformation.Invoke($null, @(
        $SysInfo.FileCache[0], $ptr, $SysInfo.FileCache[1], 0
      )) -eq 0) {
        New-Object PSObject -Property @{
          CurrentSize = [Marshal]::ReadInt32($ptr) / 1Kb
          PeakSize    = [Marshal]::ReadInt32($ptr, 4) / 1Kb
          MinimumWS   = [Marshal]::ReadInt32($ptr, 12) * $psz / 1Kb
          MaximumWS   = [Marshal]::ReadInt32($ptr, 16) * $psz / 1Kb
        } | Select-Object CurrentSize, PeakSize, MinimumWS, MaximumWS |
        Format-List
      }
    }
    catch { $_.Exception }
    finally {
      if ($ptr) { [Marshal]::FreeHGlobal($ptr) }
    }
  }
  end {
    [void]$ta::Remove('Marshal')
  }
}

#requires -version 5
function Get-ProcessOwner {
  <#
    .SYNOPSIS
        Retrieves owner of the specified process.
    .NOTES
        .NET Framework 4.5.2 is required.
  #>
  param(
    [Parameter(Mandatory=$true)]
    [ValidateScript({($script:proc = Get-Process -Id $_ -ea 0) -ne 0})]
    [Int32]$Id
  )
  
  begin {
    [Microsoft.Win32.SafeHandles.SafeAccessTokenHandle]$stah = [IntPtr]::Zero
  }
  process {
    if (![Object].Assembly.GetType(
      'Microsoft.Win32.Win32Native'
    ).GetMethod(
      'OpenProcessToken', [Reflection.BindingFlags]40
    ).Invoke($null, ($par = [Object[]]@(
      $proc.Handle, [Security.Principal.TokenAccessLevels]::Query, $stah
    )))) {
      $stah.Dispose()
      throw New-Object ComponentModel.Win32Exception(
        [Runtime.InteropServices.Marshal]::GetLastWin32Error()
      )
    }
  }
  end {
    New-Object PSObject -Property @{
      Process = $proc.Name
      PID = $proc.Id
      User = (New-Object Security.Principal.WindowsIdentity(
        $par[2].DangerousGetHandle()
      )).Name
    } | Select-Object Process, PID, User | Format-List
    
    $par[2].Dispose()
    $stah.Dispose()
  }
}

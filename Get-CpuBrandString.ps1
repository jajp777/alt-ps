function Get-CPUBrandString {
  <#
    .SYNOPSIS
        Gets CPU brand string via NtQuerySystemInformation.
    .NOTES
        Author: greg zakharov
  #>
  begin {
    if ([Environment]::OSVersion.Version.Major -lt 6) {
      throw New-Object NotSupportedException(
        'This function requres Windows Vista and higher.'
      )
    }
    
    $SystemProcessorBrandString = 105
    $NtQuerySystemInformation = [Regex].Assembly.GetType(
      'Microsoft.Win32.NativeMethods'
    ).GetMethod('NtQuerySystemInformation')
    
    # init buffer size
    $sz = [Runtime.InteropServices.Marshal]::SizeOf(
      [Activator]::CreateInstance(
        [Object].Assembly.GetType(
          'Microsoft.Win32.Win32Native+UNICODE_STRING'
        )
      )
    )
  }
  process {}
  end {
    try {
      $ret = 0
      $ptr = [Runtime.InteropServices.Marshal]::AllocHGlobal($sz)
      if ($NtQuerySystemInformation.Invoke($null, ($par = [Object[]]@(
        $SystemProcessorBrandString, $ptr, $sz, $ret
      ))) -eq 0xC0000004) { #STATUS_INFO_LENGTH_MISMATCH
        $ptr = [Runtime.InteropServices.Marshal]::ReAllocHGlobal(
          $ptr, [IntPtr]$par[3]
        )
        if ($NtQuerySystemInformation.Invoke($null, @(
          $SystemProcessorBrandString, $ptr, $par[3], $null
        )) -ne 0) {
          throw New-Object InvalidOperationException(
            'Could not retrieve processor brand string.'
          )
        }
        $buf = New-Object Byte[]($par[3])
        [Runtime.InteropServices.Marshal]::Copy($ptr, $buf, 0, $buf.Length)
        (-join [Char[]]$buf).Trim()
      }
    }
    catch { $_.Exception }
    finally {
      if ($ptr) { [Runtime.InteropServices.Marshal]::FreeHGlobal($ptr) }
    }
  }
}

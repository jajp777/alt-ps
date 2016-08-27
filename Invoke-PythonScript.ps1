function Invoke-PythonScript {
  <#
    .SYNOPSIS
        Invokes Python scripts inside current session of PowerShell host.
    .EXAMPLE
        Invoke-PythonScript @'
        from ctypes import byref, c_long, windll
        
        _max, _min, _cur = c_long(), c_long(), c_long()
        if not windll.ntdll.NtQueryTimerResolution(
           byref(_max), byref(_min), byref(_cur)
        ):
           for i in [_max, _min, _cur]:
              print('%.3f' % (i.value / 10000))
        '@
    .NOTES
        Requirements: Python should be installed and stored into PATH.
  #>
  param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [String]$Code
  )
  
  begin {}
  process {
    if (!(Get-Command -CommandType Application python -ea 0)) {
      Write-Warning "Python interpreter has not been found."
      return
    }
    
    python -c $Code
  }
  end {}
}

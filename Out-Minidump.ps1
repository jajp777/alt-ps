function Out-Minidump {
  <#
    .SYNOPSIS
        Creates a minidump of a process.
    .EXAMPLE
        PS C:\> Out-Minidump 700 -DumpType 2
  #>
  param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateScript({
      ($script:proc = Get-Process -Id $_ -ea 0) -ne $null
    })]
    [Int32]$Id,
    
    [Parameter(Position=1)]
    [ValidateSet(
      0,    #Normal
      1,    #DataSegments
      2,    #FullMemory
      4,    #HandleData
      8,    #FilterMemory
      16,   #ScanMemory
      32,   #WithUnloadedModules
      64,   #WithIndirectlyReferencedMemory
      128,  #FilterModulePath
      256,  #WithProcessThreadData
      512,  #WithPrivateReadWriteMemory
      1024, #WithoutOptionalData
      2048, #WithFullMemoryInfo
      4096, #WithThreadInfo
      8192  #WithCodeSegments
    )]
    [UInt32]$DumpType = 0,
    
    [Parameter(Position=2)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Path $_})]
    [String]$SavePath = $pwd.Path
  )
  
  begin {
    $itm = "$($proc.Name)_$($proc.Id).dmp"
    $dmp = "$SavePath\$itm"
  }
  process {
    try {
      $fs = [IO.File]::Create($dmp)
      if (![PSObject].Assembly.GetType(
        'System.Management.Automation.WindowsErrorReporting+NativeMethods'
      ).GetMethod(
        'MiniDumpWriteDump', [Reflection.BindingFlags]40
      ).Invoke(
        $null, @(
          $proc.Handle, $proc.Id, $fs.SafeFileHandle, $DumpType,
          [IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero
        )
      )) {
        $err = (New-Object ComponentModel.Win32Exception).Message
      }
    }
    finally {
      if ($fs) {
        $fs.Dispose()
        $fs.Close()
      }
    }
  }
  end {
    if ($err) {
      Remove-Item $dmp -Force -ea 0
      Write-Error $err
    }
  }
}

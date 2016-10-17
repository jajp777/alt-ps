function Get-ProcessParent {
  <#
    .SYNOPSIS
        Retrieves parent of the specified process.
    .NOTES
        Possible alternative way.
        
        param(
          [Parameter(Mandatory=$true, Position=0)]
          [ValidateNotNullOrEmpty()]
          [Int32]$Id,
          
          [Parameter(Position=1)]
          [ValidateNotNullOrEmpty()]
          [String]$MachineName = '.'
        )
        
        $pc = New-Object Diagnostics.PerformanceCounter(
          'Process', 'Creating Process ID',
          (Get-Process -Id $Id -ea 1).ProcessName, $MachineName
        )
        'Parent PID of {0} is {1}' -f $Id, $pc.RawValue
  #>
  param(
    [Parameter(Mandatory=$true)]
    [ValidateScript({($script:proc = Get-Process -Id $_)})]
    [Int32]$Id
  )
  
  begin {
    $obj = {param([String]$Name)
      [Regex].Assembly.GetType(
        "Microsoft.Win32.NativeMethods$($Name)"
      )
    }
    # OpenProcess and NtQueryInformationProcess
    $obj.Invoke()[0].GetMethods() | Where-Object {
      $_.Name -cmatch '\A(Nt|Open).*Process\Z'
    } | ForEach-Object {
      Set-Variable $_.Name $_
    }
    # NtProcessBasicInfo structure
    $NtProcessBasicInfo = $obj.Invoke(
      '+NtProcessBasicInfo'
    )[0].GetConstructor(
      [Reflection.BindingFlags]20, $null, [Type[]]@(), $null
    ).Invoke($null)
  }
  process {
    if (($sph = $OpenProcess.Invoke(
      $null, @(0x400, $false, $proc.Id)
    )).IsInvalid) {
      (New-Object ComponentModel.Win32Exception(
        [Runtime.InteropServices.Marshal]::GetLastWin32Error()
      )).Message
      return
    }
    
    if ($NtQueryInformationProcess.Invoke(
      $null, ($par = [Object[]]@(
        $sph, 0, $NtProcessBasicInfo,
        [Runtime.InteropServices.Marshal]::SizeOf($NtProcessBasicInfo),
        $null
      ))
    ) -ne 0) {
      $sph.Dispose()
      Write-Error 'Could not retrieve parent of the specified process.'
      return
    }
    
    New-Object PSObject -Property @{
      Name = $proc.Name
      PID  = $proc.Id
      PPID = ($$ = $par[2].InheritedFromUniqueProcessId)
      ParentName = ($$ = (Get-Process -Id $$ -ea 0).Name)
      ParentIsExisted = ![String]::IsNullOrEmpty($$)
    } | Select-Object Name, PID, PPID, ParentName, ParentIsExisted
  }
  end { if ($sph) { $sph.Dispose() } }
}

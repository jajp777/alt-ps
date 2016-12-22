# region of helper functions
function ConvertFrom-ProcAddress {
  [OutputType([Hashtable])]
  param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateNotNull()]
    [Object]$ProcAddress,
    
    [Parameter(Mandatory=$true, Position=1)]
    [ValidateNotNull()]
    [Type[]]$Prototype
  )
  
  begin {
    $arr = New-Object String[]($ProcAddress.Keys.Count)
    $ProcAddress.Keys.CopyTo($arr, 0)
    
    $ret = @{}
  }
  process {}
  end {
    for ($i = 0; $i -lt $arr.Length; $i++) {
      $ret[$arr[$i]] = New-Delegate $ProcAddress[$arr[$i]] $Prototype[$i]
    }
    
    $ret
  }
}

function Get-ProcAddress {
  [OutputType([Collections.Generic.Dictionary[String, IntPtr]])]
  param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateNotNullOrEmpty()]
    [String]$Module,
    
    [Parameter(Mandatory=$true, Position=1)]
    [ValidateNotNullOrEmpty()]
    [String[]]$Function
  )
  
  begin {
    [Object].Assembly.GetType(
      'Microsoft.Win32.Win32Native'
    ).GetMethods(
      [Reflection.BindingFlags]40
    ) | Where-Object {
      $_.Name -cmatch '\AGet(ProcA|ModuleH)'
    } | ForEach-Object {
      Set-Variable $_.Name $_
    }
    
    if (($ptr = $GetModuleHandle.Invoke(
      $null, @($Module)
    )) -eq [IntPtr]::Zero) {
      throw New-Object InvalidOperationException(
        'Could not find specified module.'
      )
    }
  }
  process {}
  end {
    $Function | ForEach-Object {
      $dic = New-Object "Collections.Generic.Dictionary[String, IntPtr]"
    }{
      if (($$ = $GetProcAddress.Invoke(
        $null, @($ptr, [String]$_)
      )) -ne [IntPtr]::Zero) { $dic.Add($_, $$) }
    }{ $dic }
  }
}

function New-Delegate {
  [OutputType([Type])]
  param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateScript({$_ -ne [IntPtr]::Zero})]
    [IntPtr]$ProcAddress,
    
    [Parameter(Mandatory=$true, Position=1)]
    [ValidateNotNull()]
    [Type]$Prototype,
    
    [Parameter(Position=2)]
    [ValidateNotNullOrEmpty()]
    [Runtime.InteropServices.CallingConvention]
    $CallingConvention = 'StdCall'
  )
  
  $method = $Prototype.GetMethod('Invoke')
  
  $returntype = $method.ReturnType
  $paramtypes = $method.GetParameters() |
                                 Select-Object -ExpandProperty ParameterType
  
  $holder = New-Object Reflection.Emit.DynamicMethod(
    'Invoke', $returntype, $(
      if (!$paramtypes) { $null } else { $paramtypes }
    ), $Prototype
  )
  $il = $holder.GetILGenerator()
  if ($paramtypes) {
    0..($paramtypes.Length - 1) | ForEach-Object {
      $il.Emit([Reflection.Emit.OpCodes]::Ldarg, $_)
    }
  }
  
  switch ([IntPtr]::Size) {
    4 { $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4, $ProcAddress.ToInt32()) }
    8 { $il.Emit([Reflection.Emit.OpCodes]::Ldc_I8, $ProcAddress.ToInt64()) }
  }
  $il.EmitCalli(
    [Reflection.Emit.OpCodes]::Calli, $CallingConvention, $returntype,
    $(if (!$paramtypes) { $null } else { $paramtypes })
  )
  $il.Emit([Reflection.Emit.OpCodes]::Ret)
  
  $holder.CreateDelegate($Prototype)
}
# endregion

function Get-Pipelist {
  <#
    .SYNOPSIS
        Displays the named pipes on your system, including the number
        of maximum instances and active instances for each pipe.
    .NOTES
        Author: greg zakharov
        Requirements: CLR v4
  #>
  $x = '[Func[Microsoft.Win32.SafeHandles.SafeFileHandle, ' +
       'IntPtr, IntPtr, IntPtr, [Byte[]], IntPtr, UInt32, ' +
                  'UInt32, Boolean, IntPtr, Boolean, Int32]]'

  $ntdll = Get-ProcAddress ntdll @(
    'NtQueryDirectoryFile', 'NtQuerySystemInformation'
  )
  $ntdll = ConvertFrom-ProcAddress $ntdll @(
    (Invoke-Expression $x),
    [Func[Int32, IntPtr, Int32, [Byte[]], Int32]]
  )
  
  try {
    # sizeof(SYSTEM_BASIC_INFORMATION) = 0x2C
    $sbi = [Runtime.InteropServices.Marshal]::AllocHGlobal(0x2C)
    
    if ($ntdll.NtQuerySystemInformation.Invoke(
      0, $sbi, 0x2C, $null # SystemBasicInformation = 0
    ) -ne 0) {
      throw New-Object InvalidOperationException(
        'Could not retrieve the page size.'
      )
    }
    # +0x08 PageSize : Uint4B
    $psz = [Runtime.InteropServices.Marshal]::ReadInt32($sbi, 8)
    # retrieve pipes data
    if (($pipes = [Object].Assembly.GetType(
      'Microsoft.Win32.Win32Native'
    ).GetMethod(
      'CreateFile', [Reflection.BindingFlags]40
    ).Invoke($null, @(
      '\\.\pipe\', 0x80000000, [IO.FileShare]::Read, $null,
      [IO.FileMode]::Open, 0, [IntPtr]::Zero
    ))).IsInvalid) {
      throw New-Object InvalidOperationException(
        'Could not get access for the pipes directory.'
      )
    }
    
    $query, $isb = $true, (New-Object Byte[]([IntPtr]::Size))
    $dir = [Runtime.InteropServices.Marshal]::AllocHGlobal($psz)
    
    $(while ($true) { # FileDirectoryInformation = 1
      if ($ntdll.NtQueryDirectoryFile.Invoke(
        $pipes, [IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero,
        $isb, $dir, $psz, 1, $false, [IntPtr]::Zero, $query
      ) -ne 0) { break }
      
      $tmp = $dir
      while ($true) {
        # NextEntryOffset - offset 0x00
        $neo = [Runtime.InteropServices.Marshal]::ReadInt32($tmp)
        # EndOfFile       - offset 0x28
        $eof = [Runtime.InteropServices.Marshal]::ReadInt64($tmp, 0x28)
        # AllocationSize  - offset 0x30
        $fas = [Runtime.InteropServices.Marshal]::ReadInt64($tmp, 0x30)
        # FileNameLength  - offset 0x3C
        $fnl = [Runtime.InteropServices.Marshal]::ReadInt32($tmp, 0x3C)
        # FileName        - offset 0x40
        $mov = switch ([IntPtr]::Size) { 4 {$tmp.ToInt32()} 8 {$tmp.ToInt64()} }
        
        New-Object PSObject -Property @{
          PipeName = [Runtime.InteropServices.Marshal]::PtrToStringUni(
            [IntPtr]($mov + 0x40), $fnl / 2
          )
          Instances = [BitConverter]::ToInt32([BitConverter]::GetBytes($eof), 0)
          MaxInstances = [BitConverter]::ToInt32([BitConverter]::GetBytes($fas), 0)
        }
        if ($neo -eq 0) { break }
        $tmp = [IntPtr]($mov + $neo)
      }
      
      $query = $false
    }) | Select-Object PipeName, Instances, MaxInstances
  }
  catch { $_.Message }
  finally {
    if ($dir) { [Runtime.InteropServices.Marshal]::FreeHGlobal($dir) }
    if ($pipes) { $pipes.Dispose() }
    if ($sbi) { [Runtime.InteropServices.Marshal]::FreeHGlobal($sbi) }
  }
}

# Export-ModuleMember -Function Get-Pipelist

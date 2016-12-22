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

function Get-Uptime {
  <#
    .SYNOPSIS
        Gets current system uptime.
    .NOTES
        Author: greg zakharov
        Requirements: CLR v4
  #>
  $ntdll = Get-ProcAddress ntdll NtQuerySystemInformation
  $ntdll = ConvertFrom-ProcAddress $ntdll (
     ([Func[Int32, IntPtr, Int32, [Byte[]], Int32]])
  )
  $SystemTimeOfDayInformation = 3
  
  try {
    $sti = [Runtime.InteropServices.Marshal]::AllocHGlobal(48)
    
    if ($ntdll.NtQuerySystemInformation.Invoke(
      $SystemTimeOfDayInformation, $sti, 48, $null
    ) -ne 0) {
      throw New-Object InvalidOperationException(
        'Could not retrieve system uptime.'
      )
    }
    
    $uptime = [TimeSpan]::FromMilliseconds((
      [Runtime.InteropServices.Marshal]::ReadInt64($sti, 8) -
      [Runtime.InteropServices.Marshal]::ReadInt64($sti)) / 10000
    )
  }
  catch { Write-Verbose $_ }
  finally {
    if ($sti) { [Runtime.InteropServices.Marshal]::FreeHGlobal($sti) }
  }
  
  $uptime
}

# Export-ModuleMember -Function Get-Uptime

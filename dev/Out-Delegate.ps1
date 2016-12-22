function Out-Delegate {
  <#
    .SYNOPSIS
        Creates a template of script which invokes WinAPI via Func
        or Action delegates.
    .NOTES
        Author: greg zakharov
        Requirements: CLR v4#
  #>
  param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateNotNullOrEmpty()]
    [String]$Verb,
    
    [Parameter(Mandatory=$true, Position=1)]
    [ValidateNotNullOrEmpty()]
    [String]$Noun,
    
    [Parameter()][String]$Path = $PWD
  )

$code = @'
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

function Verb-Noun {
  param()
  
  <# place your code here #>
}

# Export-ModuleMember -Function Verb-Noun
'@

  $code = $code -creplace 'Verb', $Verb
  $code = $code -creplace 'Noun', $Noun
  Out-File "$Path\$Verb-$Noun.ps1" -InputObject $code -Encoding Default
}

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

function Get-Sum {
  <#
    .NOTES
        Author: greg zakharov
  #>
  [CmdletBinding(DefaultParameterSetName='Path')]
  param(
    [Parameter(Mandatory=$true,
               ParameterSetName='Path',
               Position=0,
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [String]$Path,
    
    [Parameter(Mandatory=$true,
               ParameterSetName='LiteralPath',
               Position=0,
               ValueFromPipeline=$false,
               ValueFrompipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [Alias('PSPath')]
    [String]$LiteralPath,
    
    [Parameter()]
    [ValidateSet('CRC32', # RtlComputeCrc32
                 'MD5',   # not secure, do not use
                 'SHA1',  # not secure, do not use
                 'SHA256',
                 'SHA384',
                 'SHA512',
                 'RIPEMD160')]
    [String]$Algorithm = 'SHA256'
  )
  
  begin {
    if ($PSCmdlet.ParameterSetName -eq 'Path') {
      $PipelineInput = !$PSBoundParameters.ContainsKey('Path')
    }
    
    function private:New-Calculation {
      param(
        [Parameter(Mandatory=$true)]
        [IO.FileInfo]$File
      )
      
      if ($File.Length -eq 0) {
        Write-Verbose "$File has null length."
        return
      }
      
      if ($Algorithm -eq 'CRC32') {
        $ntdll = Get-ProcAddress ntdll RtlComputeCrc32
        $ntdll = ConvertFrom-ProcAddress $ntdll (
               [Func[UInt32, [Byte[]], Int32, UInt32]]
        )
      }
      else {
        $ha = [Security.Cryptography.HashAlgorithm]::Create(
          $Algorithm # md5, shaX and ripemd160
        )
      }
      
      try {
        $fs = [IO.File]::OpenRead($File.FullName)
        if ($ntdll) {
          [Byte[]]$buf = New-Object Byte[]($fs.Length)
          [UInt32]$crc = 0
          
          '0x{0:X}' -f $ntdll.RtlComputeCrc32.Invoke(
            $crc, $buf, ($fs.Read($buf, 0, $buf.Length))
          )
        }
        else {
          -join ($ha.ComputeHash($fs) | ForEach-Object {
            $_.ToString('x2') # lower case
          })
        }
      }
      catch { Write-Verbose $_ }
      finally {
        if ($fs) { $fs.Dispose() }
      }
    }
  }
  process {}
  end {
    if ($PSCmdlet.ParameterSetName -eq 'Path') {
      switch ($PipelineInput) {
        $true  { New-Calculation $Path }
        $false { New-Calculation (Get-Item $Path) }
      }
    }
    else { New-Calculation (Get-Item -LiteralPath $LiteralPath) }
  }
}

# Export-ModuleMember -Function Get-Sum

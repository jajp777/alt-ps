function Get-RegModifyTime {
  <#
    .SYNOPSIS
        Retrieves last-modified time stamp of a registry key.
    .EXAMPLE
        PS C:\> Get-RegModifyTime 'HKCU:\Volatile Environment'
        
        This example can be interpreted like a last logon time
        of the current user.
  #>
  param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({($script:rk = Get-Item $_ -ea 0) -ne 0})]
    [String]$RegistryKey
  )
  
  begin {
    function private:Set-Delegate {
      param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String]$Module,
        
        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String]$Function,
        
        [Parameter(Mandatory=$true, Position=2)]
        [ValidateNotNullOrEmpty()]
        [String]$Delegate
      )
      
      begin {
        [Object].Assembly.GetType(
          'Microsoft.Win32.Win32Native'
        ).GetMethods([Reflection.BindingFlags]40) |
        Where-Object {
          $_.Name -cmatch '\AGet(ProcA|ModuleH)'
        } | ForEach-Object {
          Set-Variable $_.Name $_
        }
        
        if (($ptr = $GetProcAddress.Invoke($null, @(
          $GetModuleHandle.Invoke($null, @($Module)), $Function
        ))) -eq [IntPtr]::Zero) {
          throw New-Object InvalidOperationException(
            'Could not find specified signature.'
          )
        }
      }
      process { $proto = Invoke-Expression $Delegate }
      end {
        $method = $proto.GetMethod('Invoke')
        
        $returntype = $method.ReturnType
        $paramtypes = $method.GetParameters() |
                          Select-Object -ExpandProperty ParameterType
        
        $holder = New-Object Reflection.Emit.DynamicMethod(
          'Invoke', $returntype, $paramtypes, $proto
        )
        $il = $holder.GetILGenerator()
        0..($paramtypes.Length - 1) | ForEach-Object {
          $il.Emit([Reflection.Emit.OpCodes]::Ldarg, $_)
        }
        
        switch ([IntPtr]::Size) {
          4 { $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4, $ptr.ToInt32()) }
          8 { $il.Emit([Reflection.Emit.OpCodes]::Ldc_I8, $ptr.ToInt64()) }
        }
        $il.EmitCalli(
          [Reflection.Emit.OpCodes]::Calli,
          [Runtime.InteropServices.CallingConvention]::StdCall,
          $returntype, $paramtypes
        )
        $il.Emit([Reflection.Emit.OpCodes]::Ret)
        
        $holder.CreateDelegate($proto)
      }
    }
    
    $RegQueryInfoKey = Set-Delegate advapi32 RegQueryInfoKeyW (
       '[Func[Microsoft.Win32.SafeHandles.SafeRegistryHandle, ' +
       'Text.StringBuilder, [Byte[]], UInt32, [Byte[]], [Byte[]], ' +
       '[Byte[]], [Byte[]], [Byte[]], [Byte[]], [Byte[]], [Byte[]], Int32]]')
  }
  process {
    try {
      $ft = New-Object Byte[](8) # FILETIME
      
      if ($RegQueryInfoKey.Invoke(
        $rk.Handle, $null, $null, $null, $null, $null,
        $null, $null, $null, $null, $null, $ft
      ) -ne 0) {
        throw New-Object InvalidOperationException(
          'Could not retrieve last write time of the key.'
        )
      }
      
      $low, $high = $ft[0..3], $ft[4..7] | ForEach-Object {
        [BitConverter]::ToUInt32($_, 0)
      }
      
      [DateTime]::FromFileTime(
        [Int64]($high * [Math]::Pow(2, 32)) -bor $low
      ).ToString('dd.MM.yyyy HH:mm:ss')
    }
    finally {
      if ($rk) { $rk.Dispose() }
    }
  }
  end {}
}

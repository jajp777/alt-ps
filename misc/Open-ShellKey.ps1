function Open-ShellKey {
  <#
    .SYNOPSIS
        Opens a shell key.
    .DESCRIPTION
        This function is just a wrapper for not documented function
        SHGetShellKey. SHGetShellKey is exported from shlwapi.dll as
        ordinal 491 in version 6.00 and higher.
        
        typedef enum _SHELLKEY {
           SHELLKEY_HKCU_EXPLORER    = 0x00001,
           SHELLKEY_HKLM_EXPLORER    = 0x00002,
           SHELLKEY_HKCU_SHELL       = 0x00011,
           SHELLKEY_HKLM_SHELL       = 0x00012,
           SHELLKEY_HKCU_SHELLNOROAM = 0x00021,
           SHELLKEY_HKCULM_MUICACHE  = 0x05021,
           SHELLKEY_HKCU_FILEEXTS    = 0x06001,
           SHELLKEY_HKCULS_SHELL     = 0x1FFFF
        } SHELLKEY;
    .EXAMPLE
        The next example shows how you can access to the MUICache key:
        
        $srh = Open-ShellKey 0x5021
        $rk = [Microsoft.Win32.RegistryKey]::FromHandle($srh)
        
        $rk.GetValueNames() | ForEach-Object {
          if (!$_.StartsWith('@') -and [Int32]$rk.GetValueKind($_) -ne 3) {
            New-Object PSObject -Property @{
              Path   = $_
              Desc   = $rk.GetValue($_)
              Exists = Test-Path $_
            }
          }
        } | Format-List
        
        $rk.Dispose()
        $srh.Dispose()
    .NOTES
        Author: greg zakharov
        Requirements: CLR v4
  #>
  param(
    [Parameter(Mandatory=$true)]
    [ValidateSet(0x1, 0x2, 0x11, 0x12, 0x21, 0x5021, 0x6001)]
    [UInt32]$KeyCode
  )
  
  begin {
    function Get-ProcAddress {
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
          Set-Variable $_.Name $_ -Scope Script
        }
      }
      process {}
      end {
        if (($ptr = $GetModuleHandle.Invoke(
          $null, @($Module)
        )) -eq [IntPtr]::Zero) {
          throw New-Object InvalidOperationException(
            'Could not find specified module.'
          )
        }
        
        $ret = @{}
        foreach ($f in $Function) {
          $ret[$f] = $GetProcAddress.Invoke($null, @($ptr, [String]$f))
        }
        
        $ret
      }
    }
    
    function New-Delegate {
      param(
        [Parameter(Mandatory=$true, Position=0)]
        [IntPtr]$ProcAddress,
        
        [Parameter(Mandatory=$true, Position=1)]
        [Type]$Prototype,
        
        [Parameter(Position=2)]
        [Runtime.InteropServices.CallingConvention]$CallingConvention = 'StdCall'
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
        (0..($paramtypes.Length - 1)) | ForEach-Object {
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
  }
  process {
    $kernel32 = Get-ProcAddress kernel32 ('GetProcAddress')
    $GetProcAddress = New-Delegate $kernel32.GetProcAddress  `
                                                 ([Func[IntPtr, IntPtr, IntPtr]])
    $SHGetShellKey = New-Delegate $GetProcAddress.Invoke(
      $GetModuleHandle.Invoke($null, @('shlwapi.dll')), [IntPtr]491
    ) ([Func[UInt32, [Byte[]], Byte, IntPtr]])
  }
  end {
    New-Object Microsoft.Win32.SafeHandles.SafeRegistryHandle(
      $SHGetShellKey.Invoke($KeyCode, $null, [Byte]0), $true
    )
  }
}

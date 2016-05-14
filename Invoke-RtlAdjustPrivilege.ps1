function Invoke-RtlAdjustPrivilege {
  <#
    .SYNOPSIS
        Sets up a privilege for current PowerShell host.
    .EXAMPLE
        PS C:\> Invoke-RtlAdjustPrivilege
        
        Enable SeShutdownPrivilege.
    .EXAMPLE
        PS C:\> Invoke-RtlAdjustPrivilege 19 $false
        
        Disable SeShutdownPrivilege.
    .EXAMPLE
        PS C:\> Invoke-RtlAdjustPrivilege 25
        
        Enable SeUndockPrivilege.
  #>
  param(
    [Parameter(Position=0)]
    [ValidateRange(2, 35)]
    [UInt32]$Privilege = 19, #SeShutdownPrivilege
    
    [Parameter(Position=1)]
    [Switch]$Enable = $true
  )
  
  begin {
    function private:Get-Delegate {
      param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String]$Module,
        
        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String]$Function,
        
        [Parameter(Mandatory=$true, Position=2)]
        [ValidateNotNullOrEmpty()]
        [String]$Func
      )
      
      [Regex].Assembly.GetType(
        'Microsoft.Win32.UnsafeNativeMethods'
      ).GetMethods() | Where-Object {
        $_.Name -cmatch '\AGet(ProcA|ModuleH)'
      } | ForEach-Object {
        Set-Variable $_.Name $_
      }
      
      try {
        $ptr = $GetProcAddress.Invoke($null, @(
          [Runtime.InteropServices.HandleRef](
          New-Object Runtime.InteropServices.HandleRef(
            (New-Object IntPtr),
            $GetModuleHandle.Invoke($null, @($Module))
          )), $Function
        ))
        
        $delegate = Invoke-Expression $Func
        $method   = $delegate.GetMethod('Invoke')
        
        $returntype = $method.ReturnType
        $paramtypes = $method.GetParameters() |
                                     Select-Object -ExpandProperty ParameterType
        
        $holder = New-Object Reflection.Emit.DynamicMethod(
          'Invoke', $returntype, $paramtypes, [Delegate]
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
      }
      catch { $_.Exception }
      finally {
        if ($holder -ne $null) {
          Set-Variable $Function $holder.CreateDelegate($delegate) -Scope Script
        }
      }
    }
  }
  process {
    Get-Delegate ntdll RtlAdjustPrivilege `
    '[Func[UInt32, Boolean, Boolean, Text.StringBuilder, Int32]]'
    $enabled = New-Object Text.StringBuilder
    
    [void]$RtlAdjustPrivilege.Invoke($Privilege, $Enable, $false, $enabled)
  }
  end {}
}

function Set-PSPrivilege {
  <#
    .SYNOPSIS
        Sets up a privilege for current PowerShell host.
    .EXAMPLE
        PS C:\> Set-PSPrivilege -Enable
        Enable SeShutdownPrivilege.
    .EXAMPLE
        PS C:\> Set-PSPrivilege
        Disable SeShutdownPrivilege.
    .NOTES
        Author: greg zakharov
  #>
  param(
    [Parameter()]
    [ValidateRange(2, 35)]
    [UInt32]$Privilege = 19, # SeShutdownPrivilege

    [Parameter()][Switch]$Enable
  )

  begin {
    function private:New-Delegate {
      param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String]$Module,

        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String]$Function,

        [Parameter(Mandatory=$true, Position=2)]
        [ValidateNotNull()]
        [Type]$Prototype
      )

      begin {
        [Regex].Assembly.GetType(
          'Microsoft.Win32.UnsafeNativeMethods'
        ).GetMethods() | Where-Object {
          $_.Name -cmatch '\AGet(ProcA|ModuleH)'
        } | ForEach-Object {
          Set-Variable $_.Name $_
        }

        if (($ptr = $GetProcAddress.Invoke($null, @(
          [Runtime.InteropServices.HandleRef](
          New-Object Runtime.InteropServices.HandleRef(
            (New-Object IntPtr),
            $GetModuleHandle.Invoke($null, @($Module))
          )), $Function
        ))) -eq [IntPtr]::Zero) {
          throw New-Object InvalidOperationException(
            'Could not find specified signature.'
          )
        }
      }
      process {}
      end {
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
          4 { $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4, $ptr.ToInt32()) }
          8 { $il.Emit([Reflection.Emit.OpCodes]::Ldc_I8, $ptr.ToInt64()) }
        }
        $il.EmitCalli(
          [Reflection.Emit.OpCodes]::Calli,
          [Runtime.InteropServices.CallingConvention]::StdCall,
          $returntype, $(if (!$paramtypes) { $null } else { $paramtypes })
        )
        $il.Emit([Reflection.Emit.OpCodes]::Ret)

        $holder.CreateDelegate($Prototype)
      }
    }
  }
  process {}
  end {
    $enabled = New-Object Text.StringBuilder
    if (($nts = (New-Delegate ntdll RtlAdjustPrivilege (
      [Func[UInt32, Boolean, Boolean, Text.StringBuilder, Int32]]
    )).Invoke($Privilege, $Enable, $false, $enabled)) -ne 0) {
      throw New-Object InvalidOperationException('NTSTATUS: {0:X}' -f $nts)
    }
  }
}

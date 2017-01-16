function New-HardLink {
  <#
    .SYNOPSIS
        Establishes a hard link between an existing file and a new file.
    .DESCRIPTION
        This function is only supported on the NTFS file system, and
        only for files, not directories.
    .PARAMETER Source
        The name of the existing file.
    .PARAMETER Destination
        The name of the new file (should be a full path).
    .EXAMPLE
        PS C:\Users\Admin> New-HardLink .\Documents\src.c C:\src\target.c
    .OUTPUTS
        If the function succeeds, the return value is $true.
    .NOTES
        Author: greg zakharov
  #>
  param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Path $_})]
    [String]$Source,

    [Parameter(Mandatory=$true, Position=1)]
    [ValidateNotNullOrEmpty()]
    [String]$Destination
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
    (New-Delegate kernel32 CreateHardLinkW (
      [Func[[Byte[]], [Byte[]], IntPtr, Boolean]]
    )).Invoke(
      [Text.Encoding]::Unicode.GetBytes($Destination),
      [Text.Encoding]::Unicode.GetBytes((Convert-Path $Source)),
      [IntPtr]::Zero
    )
  }
}

function Hide-Cursor {
  <#
    .SYNOPSIS
        Makes mouse cursor [in]visible in console window.
    .NOTES
        Author: greg zakharov
  #>
  param([Switch]$Cancel)
  
  begin {
    function private:New-Delegate {
      param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]$Module,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]$Function,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [Type]$Prototype
      )
      
      begin {
        [Object].Assembly.GetType(
          'Microsoft.Win32.Win32Native'
        ).GetMethods([Reflection.BindingFlags]40) |
        Where-Object {
          $_.Name -cmatch '\AGet(ProcA|ModuleH)'
        } | ForEach-Object { Set-Variable $_.Name $_ }
        
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
    
    $ShowConsoleCursor = New-Delegate kernel32 ShowConsoleCursor `
                                                ([Action[IntPtr, Boolean]])
  }
  process {}
  end {
    $ShowConsoleCursor.Invoke(
      ([Object].Assembly.GetType(
        'Microsoft.Win32.Win32Native'
      ).GetMethod(
        'GetStdHandle', [Reflection.BindingFlags]40
      ).Invoke($null, @(-11))), $Cancel
    )
  }
}

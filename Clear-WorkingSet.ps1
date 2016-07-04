function Clear-WorkingSet {
  <#
    .SYNOPSIS
        Sets the minimum working set sizes for the specified process.
  #>
  param(
    [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
    [ValidateScript({(Get-Process -Id $_ -ea 0) -ne $null})]
    [Int32]$Id
  )
  
  begin {
    @(
      [Runtime.InteropServices.CallingConvention],
      [Runtime.InteropServices.HandleRef],
      [Reflection.Emit.OpCodes]
    ) | ForEach-Object {
      $keys = ($ta = [PSObject].Assembly.GetType(
        'System.Management.Automation.TypeAccelerators'
      ))::Get.Keys
      $collect = @()
    }{
      if ($keys -notcontains $_.Name) {
        $ta::Add($_.Name, $_)
      }
      $collect += $_.Name
    }
    
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
        [Regex].Assembly.GetType(
          'Microsoft.Win32.UnsafeNativeMethods'
        ).GetMethods() | Where-Object {
          $_.Name -cmatch '\AGet(ProcA|ModuleH)'
        } | ForEach-Object {
          Set-Variable $_.Name $_
        }
        
        $ptr = $GetProcAddress.Invoke($null, @(
          [HandleRef](New-Object HandleRef(
            (New-Object IntPtr), $GetModuleHandle.Invoke($null, @($Module))
          )), $Function
        ))
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
          $il.Emit([OpCodes]::Ldarg, $_)
        }
        
        switch ([IntPtr]::Size) {
          4 { $il.Emit([OpCodes]::Ldc_I4, $ptr.ToInt32()) }
          8 { $il.Emit([OpCodes]::Ldc_I8, $ptr.ToInt64()) }
        }
        $il.EmitCalli(
          [OpCodes]::Calli, [CallingConvention]::StdCall, $returntype, $paramtypes
        )
        $il.Emit([OpCodes]::Ret)
        
        $holder.CreateDelegate($proto)
      }
    }
    
    $SetProcessWorkingSetSize = Set-Delegate kernel32 SetProcessWorkingSetSize `
                                            '[Func[IntPtr, Int32, Int32, Boolean]]'
  }
  process {
    $SetProcessWorkingSetSize.Invoke((Get-Process -Id $Id).Handle, -1, -1)
  }
  end {
    $collect | ForEach-Object { [void]$ta::Remove($_) }
  }
}

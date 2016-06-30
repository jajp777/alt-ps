function Find-MsiPackage {
  <#
    .SYNOPSIS
        Gets packages deployed with msiexec service.
    .EXAMPLE
        PS C:\>  Find-MsiPackage
        Prints names of all packages deployed with msiexec.
    .EXAMPLE
        PS C:\> Find-MsiPackage microsoft
        Searches all packages which contains "microsoft" word in their names.
  #>
  param(
    [Parameter(ValueFromPipeline=$true)]
    [ValidateNotNullOrEmpty()]
    [String]$Package
  )
  
  begin {
    @(
      [Runtime.InteropServices.CallingConvention],
      [Runtime.InteropServices.Marshal],
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
    
    function private:Get-ProcAddress {
      param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String]$Module,
        
        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String]$Function
      )
      
      [Data.Rule].Assembly.GetType(
        'System.Data.Common.SafeNativeMethods'
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
        if (($mod = [Regex].Assembly.GetType(
          'Microsoft.Win32.SafeNativeMethods'
        ).GetMethod('LoadLibrary').Invoke(
          $null, @($Module)
        )) -eq [IntPtr]::Zero) {
          (New-Object ComponentModel.Win32Exception(
            [Marshal]::GetLastWin32Error()
          )).Message
          break
        }
        $ptr = $GetModuleHandle.Invoke($null, @($Module))
      }
      $GetProcAddress.Invoke($null, @($ptr, $Function)), $mod
    }
    
    function private:Invoke-FreeLibrary {
      param(
        [Parameter(Mandatory=$true)]
        [IntPtr]$ModuleHandle
      )
      
      [void][Linq.Enumerable].Assembly.GetType(
        'Microsoft.Win32.UnsafeNativeMethods'
      ).GetMethod(
        'FreeLibrary', [Reflection.BindingFlags]40
      ).Invoke($null, @($ModuleHandle))
    }
    
    function Set-Delegate {
      param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateScript({$_ -ne [IntPtr]::Zero})]
        [IntPtr]$ProcAddress,
        
        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String]$Delegate
      )
      
      $proto = Invoke-Expression $Delegate
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
        4 { $il.Emit([OpCodes]::Ldc_I4, $ProcAddress.ToInt32()) }
        8 { $il.Emit([OpCodes]::Ldc_I8, $ProcAddress.ToInt64()) }
      }
      
      $il.EmitCalli(
        [OpCodes]::Calli, [CallingConvention]::StdCall, $returntype, $paramtypes
      )
      $il.Emit([OpCodes]::Ret)
      
      $holder.CreateDelegate($proto)
    }
  }
  process {
    $ptr, $mod = Get-ProcAddress msi MsiEnumProductsA
    $MsiEnumProducts = Set-Delegate $ptr '[Func[Int32, Text.StringBuilder, Int32]]'
    $ptr, $null = Get-ProcAddress msi MsiGetProductInfoA
    $MsiGetProductInfo = Set-Delegate $ptr `
            '[Func[String, String, Text.StringBuilder, Text.StringBuilder, Int32]]'
    
    $guid = New-Object Text.StringBuilder(39)
    $(for ($i = 0; $err -ne 259; $i++) {
      if (($err = $MsiEnumProducts.Invoke($i, $guid)) -eq 0) {
        [Int32]$len = 0x200
        $buf = New-Object Text.StringBuilder($len)
        $rsz = New-Object Text.StringBuilder
        
        New-Object PSObject -Property @{
          Name = $(if (($err = $MsiGetProductInfo.Invoke(
            $guid.ToString(), 'ProductName', $buf, $rsz
          )) -eq 0) {
            $buf.ToString()
          })
          Guid = $guid.ToString()
        }
      }
    }) | Where-Object { $_.Name -match $Package }
  }
  end {
    if ($mod) { Invoke-FreeLibrary $mod }
    $collect | ForEach-Object { [void]$ta::Remove($_) }
  }
}

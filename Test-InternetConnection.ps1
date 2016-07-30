function Test-InternetConnection {
  <#
    .SYNOPSIS
        Check if a connection to the Internet can be established.
    .EXAMPLE
        PS C:\> Test-InternetConnection
    .EXMAPLE
        PS C:\> Test-InternetConnection github.com
    .NOTES
        There is well known way to do this (since .NET Framework v2).
        
        [Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable()
        
        It is just the wrapper for static method InternalGetIsNetworkAvailable
        which stored into System.Net.NetworkInformation.SystemNetworkInterface.
        
        [Regex].Assembly.GetType(
          'System.Net.NetworkInformation.SystemNetworkInterface'
        ).GetMethod(
          'InternalGetIsNetworkAvailable', [Reflection.BindingFlags]40
        ).Invoke($null, @())
        
        In turn, this method is also the wrapper for WinAPI function which
        called InternetGetConnectedState (in CLR v2, in higher versions logic
        has been changed).
        
        [UInt32]$flags = 0
        if ([Regex].Assembly.GetType(
          'System.Net.NetworkInformation.UnsafeWinINetNativeMethods'
        ).GetMethod(
          'InternetGetConnectedState', [Reflection.BindingFlags]40
        ).Invoke($null, ($par = [Object[]]($flags, [UInt32]0)))) {
          $par[0] -ne 0
        }
  #>
  param(
    [Parameter(ValueFromPipeline=$true)]
    [ValidateNotNullOrEmpty()]
    [String]$Url = 'http://www.google.com/'
  )
  
  begin {
    @(
      [Runtime.InteropServices.CallingConvention],
      [Runtime.InteropServices.HandleRef],
      [Runtime.InteropServices.Marshal],
      [Reflection.BindingFlags],
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
    
    function Get-LastError {
      param(
        [Int32]$ErrorCode = [Marshal]::GetLastWin32Error()
      )
      
      [PSObject].Assembly.GetType(
        'Microsoft.PowerShell.Commands.Internal.Win32Native'
      ).GetMethod(
        'GetMessage', [BindingFlags]40
      ).Invoke(
        $null, @($ErrorCode)
      )
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
      }
      process {
        if (($ptr = $GetModuleHandle.Invoke(
          $null, @($Module)
        )) -eq [IntPtr]::Zero) {
          if (($mod = [Regex].Assembly.GetType(
            'Microsoft.Win32.SafeNativeMethods'
          ).GetMethod('LoadLibrary').Invoke(
            $null, @($Module)
          )) -eq [IntPtr]::Zero) {
            Write-Warning "$(Get-LastError)"
            break
          }
          if (($ptr = $GetProcAddress.Invoke($null, @(
            [HandleRef](New-Object HandleRef(
               (New-Object IntPtr),
               $GetModuleHandle.Invoke($null, @($Module)))
            ), $Function
          ))) -eq [IntPtr]::Zero) {
            Write-Warning "$(Get-LastError)"
            break
          }
        }
        
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
          4 { $il.Emit([OpCodes]::Ldc_I4, $ptr.ToInt32()) }
          8 { $il.Emit([OpCodes]::Ldc_I8, $ptr.ToInt64()) }
        }
        $il.EmitCalli(
          [OpCodes]::Calli, [CallingConvention]::StdCall, $returntype, $paramtypes
        )
        $il.Emit([OpCodes]::Ret)
      }
      end { $holder.CreateDelegate($proto), $mod }
    }
    
    $InternetCheckConnection, $mod = Set-Delegate wininet InternetCheckConnectionW `
                                         '[Func[[Byte[]], UInt32, UInt32, Boolean]]'
  }
  process {
    if ([String]::IsNullOrEmpty(([Uri]$Url).AbsoluteUri)) { $Url = "http://$Url" }
    $InternetCheckConnection.Invoke([Text.Encoding]::Unicode.GetBytes($url), 1, 0)
  }
  end {
    if ($mod) {
      [void][Linq.Enumerable].Assembly.GetType(
        'Microsoft.Win32.UnsafeNativeMethods'
      ).GetMethod(
        'FreeLibrary', [BindingFlags]40
      ).Invoke($null, @($mod))
    }
    $collect | ForEach-Object { [void]$ta::Remove($_) }
  }
}

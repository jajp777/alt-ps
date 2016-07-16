function Test-Is64BitSystem {
  <#
    .SYNOPSIS
        Checks whether operation system 64-bit.
    .DESCRIPTION
        Because Environment type hasn't property Is64BitOperatingSystem
        in CLR v2 this trouble can be solved with WMI class
        Win32_OperatingSystem (property OSArchitecture). Alternatively,
        we can use IsWow64ProcessDelegate type stored in
        Microsoft.Build.Tasks.dll assembly.
  #>
  begin {
    @(
      [Runtime.InteropServices.HandleRef],
      [Runtime.InteropServices.Marshal]
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
  }
  process {
    if ($PSVersionTable.CLRVersion.Major -eq 2) {
      [Regex].Assembly.GetType(
        'Microsoft.Win32.UnsafeNativeMethods'
      ).GetMethods() | Where-Object {
        $_.Name -cmatch '\AGet(ProcA|ModuleH)'
      } | ForEach-Object {
        Set-Variable $_.Name $_
      }
      
      $ptr, $ret = $GetProcAddress.Invoke($null, @(
        [HandleRef](New-Object HandleRef(
          (New-Object IntPtr),
          $GetModuleHandle.Invoke($null, @('kernel32.dll'))
        )), 'IsWow64Process'
      )), $false
      
      Add-Type -AssemblyName ($$ = 'Microsoft.Build.Tasks')
      
      [void][Marshal]::GetDelegateForFunctionPointer(
        $ptr, ([AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object {
          $_.ManifestModule.ScopeName.Equals("$($$).dll")
        }).GetType(
          "$($$).ProcessorArchitecture+IsWow64ProcessDelegate"
        )
      ).Invoke(
        [Diagnostics.Process]::GetCurrentProcess().Handle,
        [ref]$ret
      )
      [Boolean](([IntPtr]::Size -eq 8) -bor $ret)
    }
    else { [Environment]::Is64BitOperatingSystem }
  }
  end {
    $collect | ForEach-Object { [void]$ta::Remove($_) }
  }
}

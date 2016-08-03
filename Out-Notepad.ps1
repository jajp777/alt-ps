function Out-Notepad {
  <#
    .SYNOPSIS
        Moves host output data to Notepad.
    .EXAMPLE
        PS C:\> Get-ChildItems | Out-String | Out-Notepad
  #>
  param(
    [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
    [AllowEmptyString()]
    [String]$Value
  )
  
  begin {
    Add-Type -AssemblyName ($asm = 'UIAutomationClientsideProviders')
    
    @(
      [Runtime.InteropServices.HandleRef],
      [Runtime.InteropServices.GCHandle],
      [Text.Encoding]
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
    $gch = [GCHandle]::Alloc(
      [Encoding]::Unicode.GetBytes($Value), 'Pinned'
    )
  }
  end {
    $np = Start-Process notepad -PassThru
    [void]$np.WaitForInputIdle()
    
    [void][Regex].Assembly.GetType(
      'Microsoft.Win32.UnsafeNativeMethods'
    ).GetMethod('SendMessage').Invoke($null, @(
      [HandleRef](New-Object HandleRef(
        (New-Object IntPtr),
        ([AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object {
          $_.ManifestModule.ScopeName.Equals("$asm.dll")
        }).GetType('MS.Win32.UnsafeNativeMethods').GetMethod(
          'FindWindowEx', [Reflection.BindingFlags]40
        ).Invoke($null, @(
          $np.MainWindowHandle, [IntPtr]::Zero, 'Edit', $null
        ))
      )), 0xC, [IntPtr]::Zero, $gch.AddrOfPinnedObject()
    ))
    
    if ($gch) { $gch.Free() }
    $collect | ForEach-Object { [void]$ta::Remove($_) }
  }
}

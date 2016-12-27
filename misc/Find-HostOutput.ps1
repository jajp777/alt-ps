function Find-HostOutput {
  <#
    .SYNOPSIS
        Initiates the search for a word in the current PowerShell
        host output.
    .DESCRIPTION
        This function just invokes "Find" of the popup menu which
        appears on pressing Alt+Space.
        Press Escape key twice to stop searching.
    .NOTES
        You can get some interesting effects with changing 0xfff4.
        For example:
           0xfff1 => "Paste" (be careful!)
           0xfff2 => "Mark"
           0xfff3 => "Scroll"
           0xfff5 => "Select All"
        
        Author: greg zakharov
  #>
  begin {
    if (($ta = ($asm = [PSObject].Assembly).GetType(
      'System.Management.Automation.TypeAccelerators'
    ))::Get.Keys -notcontains 'HandleRef') {
      $ta::Add('HandleRef', [Runtime.InteropServices.HandleRef])
    }
  }
  process {
    $href = New-Object HandleRef(
      (New-Object IntPtr),
      $asm.GetType(
        'System.Management.Automation.ConsoleVisibility'
      ).GetMethod(
        'GetConsoleWindow', [Reflection.BindingFlags]40
      ).Invoke($null, @())
    )
    
    [void][Regex].Assembly.GetType(
      'Microsoft.Win32.UnsafeNativeMethods'
    ).GetMethod('SendMessage').Invoke($null, @(
      [HandleRef]$href, 0x0111, [IntPtr]0xfff4, [IntPtr]::Zero
    ))
  }
  end { [void]$ta::Remove('HandleRef') }
}

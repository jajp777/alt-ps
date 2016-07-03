function Get-PSCommandLine {
  <#
    .SYNOPSIS
        Gets command line of current PowerShell host.
    .NOTES
        Of course, you can use for this purpose next code:
        
        gwmi Win32_Process | ? {$_.ProcessId -eq $PID} | select -exp CommandLine
        
        Code below is just a concept how you can do same without WMI, it was
        developed and tested on 32-bit version of Windows.
  #>
  begin {
    @(
      [Runtime.InteropServices.Marshal],
      [Runtime.InteropServices.GCHandle],
      [Reflection.BindingFlags]
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
    
    [Regex].Assembly.GetType(
      'Microsoft.Win32.NativeMethods'
    ).GetMethods() | Where-Object {
      $_.Name -cmatch '\A(Nt|Open).*Process\Z'
    } | ForEach-Object {
      Set-Variable $_.Name $_
    }
    
    $NtProcessBasicInfo = [Regex].Assembly.GetType(
      'Microsoft.Win32.NativeMethods+NtProcessBasicInfo'
    ).GetConstructor(
      [BindingFlags]20, $null, [Type[]]@(), $null
    ).Invoke($null)
    
    $UNICODE_STRING = [Activator]::CreateInstance(
      [Object].Assembly.GetType(
        'Microsoft.Win32.Win32Native+UNICODE_INTPTR_STRING'
      )
    )
    
    function private:Read-Bytes {
      param(
        [Parameter(Mandatory=$true, Position=0)]
        [IntPtr]$Pointer,
        
        [Parameter(Mandatory=$true, Position=1)]
        [Int32]$DataLength
      )
      
      0..($DataLength - 1) | ForEach-Object {$ofb = 0}{
        [Marshal]::ReadByte($Pointer, $ofb)
        $ofb++
      }
    }
  }
  process {
    if (($sph = $OpenProcess.Invoke($null, @(0x410, $false, $PID))).IsInvalid) {
      [PSObject].Assembly.GetType(
        'Microsoft.PowerShell.Commands.Internal.Win32Native'
      ).GetMethod(
        'GetMessage', [BindingFlags]40
      ).Invoke($null, @([Marshal]::GetLastWin32Error()))
      break
    }
    
    [Int32[]]$ret = @()
    if ($NtQueryInformationProcess.Invoke($null, ($par = [Object[]]@(
      $sph, 0, $NtProcessBasicInfo, [Marshal]::SizeOf($NtProcessBasicInfo), $ret
    ))) -eq 0) {
      $ptr = [Marshal]::ReadIntPtr([IntPtr]($par[2].PebBaseAddress.ToInt32() + 0x10))
      $ptr = [IntPtr]($ptr.ToInt32() + 0x40) #UNICODE_STRING offset
      [Byte[]]$bytes = Read-Bytes $ptr ([Marshal]::SizeOf($UNICODE_STRING))
      
      $gch = [GCHandle]::Alloc($bytes, 'Pinned')
      $uni = [Marshal]::PtrToStructure(
        $gch.AddrOfPinnedObject(), [Type]$UNICODE_STRING.GetType()
      )
      $gch.Free()
      
      $uni.GetType().GetFields([BindingFlags]36) | Where-Object {
        $_.Name -cmatch '\A(Buffer|Length)'
      } | ForEach-Object { Set-Variable $_.Name $_.GetValue($uni)}
      
      [Byte[]]$bytes = Read-Bytes $Buffer $Length
      [Text.Encoding]::Unicode.GetString($bytes)
    }
  }
  end {
    if ($sph -ne $null) {
      $sph.Dispose()
      $sph.Close()
    }
    
    $collect | ForEach-Object { [void]$ta::Remove($_) }
  }
}

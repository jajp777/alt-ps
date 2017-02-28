function Get-ProcessState {
  <#
    .SYNOPSIS
        Checks a process current state (running or suspended).
    .NOTES
        Author: greg zakharov

        Immediately following SYSTEM_PROCESS_INFORMATION is an
        array of zero or more SYSTEM_THREAD_INFORMATION
        structures if the information class is
        SystemProcessInformation(5), else
        SYSTEM_EXTENDED_THREAD_INFORMATION structures. Either
        way, the second field of SYSTEM_PROCESS_INFORMATION
        (NumberOfThreads) tells how to many.
  #>
  param(
    [Parameter(Mandatory=$true)]
    [Int32]$Id
  )

  begin {
    Set-Variable ($$ = [Regex].Assembly.GetType(
      'Microsoft.Win32.NativeMethods'
    ).GetMethod('NtQuerySystemInformation')).Name $$

    $UNICODE_STRING = [Activator]::CreateInstance(
      [Object].Assembly.GetType(
        'Microsoft.Win32.Win32Native+UNICODE_STRING'
      )
    )

    @(
      [Runtime.InteropServices.GCHandle],
      [Runtime.InteropServices.Marshal],
      [Reflection.BindingFlags]
    ) | ForEach-Object {
      $keys = ($ta = [PSObject].Assembly.GetType(
        'System.Management.Automation.TypeAccelerators'
      ))::Get.Keys
      $collect = @()
    }{
      if ($keys -notcontains $_.Name) { $ta::Add($_.Name, $_) }
      $collect += $_.Name
    }
  }
  process {
    try {
      $ptr, $ret = [Marshal]::AllocHGlobal(1024), 0

      if ($NtQuerySystemInformation.Invoke($null, (
        $par = [Object[]]@(5, $ptr, 1024, $ret)
      )) -eq 0xC0000004) {
        $ptr = [Marshal]::ReAllocHGlobal($ptr, [IntPtr]$par[3])
        if (($nts = $NtQuerySystemInformation.Invoke($null, (
          $par = [Object[]]@(5, $ptr, $par[3], 0)
        ))) -ne 0) {
          throw New-Object InvalidOperationException(
            'NTSTATUS: 0x{0:X}' -f $nts
          )
        }
      }

      $tmp = $ptr
      while (($$ = [Marshal]::ReadInt32($tmp))) {
        if ($(switch ([IntPtr]::Size) {
          4 { [Marshal]::ReadIntPtr($tmp, 0x44) }
          8 { [Marshal]::ReadIntPtr($tmp, 0x50) }
        }) -eq $Id) {
          $len = [Marshal]::SizeOf($UNICODE_STRING) - 1
          [Byte[]]$bytes = 0..$len | ForEach-Object {$ofb = 0x38}{
            [Marshal]::ReadByte($tmp, $ofb)
            $ofb++
          }

          $gch = [GCHandle]::Alloc($bytes, 'Pinned')
          $uni = [Marshal]::PtrToStructure(
            $gch.AddrOfPinnedObject(), [Type]$UNICODE_STRING.GetType()
          )
          $gch.Free()

          $thread_state, $wait_reason = switch ([IntPtr]::Size) {
            4 { @(0xEC, 0xF0) } 8 { @(0x144, 0x148) }
          }
          [Marshal]::ReadInt32($tmp, $thread_state
          ), [Marshal]::ReadInt32($tmp, $wait_reason
          ) | ForEach-Object {
            $suspend = if ($_ -eq 5) { $true } else { $false }
          }

          Write-Host "The process $Id ($($uni.GetType().GetField(
            'Buffer', [BindingFlags]36
          ).GetValue($uni))) is " -NoNewline
          Write-Host "$(
            if (![Boolean]$suspend) {'not '}
          )" -ForegroundColor magenta -NoNewline
          Write-Host "suspended.`n"

          break
        }

        $tmp = [IntPtr]($(switch ([IntPtr]::Size) {
          4 { $tmp.ToInt32() } 8 { $tmp.ToInt64() }
        }) + $$)
      }
    }
    catch { $_ }
    finally {
      if ($ptr) { [Marshal]::FreeHGlobal($ptr) }
    }
  }
  end {  $collect | ForEach-Object { [void]$ta::Remove($_) } }
}

function Get-ProcessTree {
  <#
    .NOTES
        This script has been written and tested on Win7 x86.
  #>
  begin {
    Set-Variable ($$ = [Regex].Assembly.GetType(
      'Microsoft.Win32.NativeMethods'
    ).GetMethod('NtQuerySystemInformation')).Name $$
    
    $UNICODE_STRING = [Activator]::CreateInstance(
      [Object].Assembly.GetType(
        'Microsoft.Win32.Win32Native+UNICODE_STRING'
      )
    )
    
    function Get-ProcessChild {
      param(
        [Parameter(Mandatory=$true, Position=0)]
        [PSObject]$Process,
        
        [Parameter(Position=1)]
        [Int32]$Depth = 1
      )
      
      $Processes | Where-Object {
        $_.PPID -eq $Process.PID -and $_.PPID -ne 0
      } | ForEach-Object {
        "$("$([Char]32)" * 2 * $Depth)$($_.ProcessName) ($($_.PID))"
        Get-ProcessChild $_ (++$Depth)
        $Depth--
      }
    }
    
    if (($ta = [PSObject].Assembly.GetType(
      'System.Management.Automation.TypeAccelerators'
    ))::Get.Keys -notcontains 'Marshal') {
      $ta::Add('Marshal', [Runtime.InteropServices.Marshal])
    }
  }
  process {
    try {
      $ret = 0
      $ptr = [Marshal]::AllocHGlobal(1024)
      
      if ($NtQuerySystemInformation.Invoke($null, (
        $par = [Object[]]@(5, $ptr, 1024, $ret)
      )) -eq 0xC0000004) { #STATUS_INFO_LENGTH_MISMATCH
        $ptr = [Marshal]::ReAllocHGlobal($ptr, [IntPtr]$par[3])
        if (($nts = $NtQuerySystemInformation.Invoke($null, (
          $par = [Object[]]@(5, $ptr, $par[3], 0)
        ))) -ne 0) {
          throw New-Object InvalidOperationException(
            'NTSTATUS: 0x{0:X}' -f $nts
          )
        }
      }
      
      $len = [Marshal]::SizeOf($UNICODE_STRING) - 1
      $tmp = $ptr
      $Processes = while (($$ = [Marshal]::ReadInt32($tmp))) {
        [Byte[]]$bytes = 0..$len | ForEach-Object {$ofb = 0x38}{
          [Marshal]::ReadByte($tmp, $ofb)
          $ofb++
        }
        
        $gch = [Runtime.InteropServices.GCHandle]::Alloc($bytes, 'Pinned')
        $uni = [Marshal]::PtrToStructure(
          $gch.AddrOfPinnedObject(), [Type]$UNICODE_STRING.GetType()
        )
        $gch.Free()
        
        New-Object PSObject -Property @{
          ProcessName = if ([String]::IsNullOrEmpty((
            $proc = $uni.GetType().GetField(
              'Buffer', [Reflection.BindingFlags]36
            ).GetValue($uni))
          )) { 'Idle' } else { $proc }
          PID = [Marshal]::ReadInt32($tmp, 0x44)
          PPID = [Marshal]::ReadInt32($tmp, 0x48)
        }
        $tmp = [IntPtr]($tmp.ToInt32() + $$)
      }
    }
    catch { $_.Exception }
    finally {
      if ($ptr -ne $null) {
        [Marshal]::FreeHGlobal($ptr)
      }
    }
  }
  end {
    if ($Processes -eq $null) {
      break
    }
    
    $Processes | Where-Object {
      -not (Get-Process -Id $_.PPID -ea 0) -or $_.PPID -eq 0
    } | ForEach-Object {
      "$($_.ProcessName) ($($_.PID))"
      Get-ProcessChild $_
    }
    
    [void]$ta::Remove('Marshal')
  }
}

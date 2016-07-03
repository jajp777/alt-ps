function Get-SystemPageFiles {
  <#
    .SYNOPSIS
        Gets list of the system page files.
    .NOTES
        #define SystemPageFileInformation 18
        
        typedef struct _SYSTEM_PAGEFILE_INFORMATION {
            ULONG NextEntryOffset;
            ULONG TotalSize;
            ULONG TotalInUse;
            ULONG PeakUsage;
            UNICODE_STRING PageFileName;
        } SYSTEM_PAGEFILE_INFORMATION, *PSYSTEM_PAGEFILE_INFORMATION;
        
        sizeof(SYSTEM_PAGEFILE_INFORMATION) = 0x18
  #>
  begin {
    @(
      [Runtime.InteropServices.Marshal],
      [Runtime.InteropServices.GCHandle]
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
    
    Set-Variable ($$ = [Regex].Assembly.GetType(
      'Microsoft.Win32.NativeMethods'
    ).GetMethod('NtQuerySystemInformation')).Name $$
    
    $UNICODE_STRING = [Activator]::CreateInstance(
      [Object].Assembly.GetType(
        'Microsoft.Win32.Win32Native+UNICODE_STRING'
      )
    )
    
    [Int32]$sz = 0x18
  }
  process {
    try {
      $ptr = [Marshal]::AllocHGlobal($sz)
      
      while ($NtQuerySystemInformation.Invoke(
        $null, @(18, $ptr, $sz, 0)
      ) -eq 0xC0000004) {
        $ptr = [Marshal]::ReAllocHGlobal($ptr, [IntPtr]($sz *= 2))
      }
      
      $len = [Marshal]::SizeOf($UNICODE_STRING) - 1
      $tmp = $ptr
      do {
        $neo = [Marshal]::ReadInt32($tmp) #NextEntryOffset
        [Byte[]]$bytes = 0..$len | ForEach-Object {$ofb = 0x10}{
          [Marshal]::ReadByte($tmp, $ofb)
          $ofb++
        }
        
        $gch = [GCHandle]::Alloc($bytes, 'Pinned')
        $uni = [Marshal]::PtrToStructure(
          $gch.AddrOfPinnedObject(), [Type]$UNICODE_STRING.GetType()
        )
        $gch.Free()
        
        $uni.GetType().GetField(
          'Buffer', [Reflection.BindingFlags]36
        ).GetValue($uni)
        
        $tmp = [IntPtr]($tmp.ToInt32() + $neo)
      } while ($neo)
    }
    catch { $_.Exception }
    finally {
      if ($ptr -ne $null) {
        [Marshal]::FreeHGlobal($ptr)
      }
    }
  }
  end {
    $collect | ForEach-Object { [void]$ta::Remove($_) }
  }
}

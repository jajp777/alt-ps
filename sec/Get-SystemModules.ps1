function Get-SystemModules {
  <#
    .SYNOPSIS
        Gets list of loaded drivers and modules.
    .NOTES
        Author: greg zakharov

        typedef struct _RTL_PROCESS_MODULE_INFORMATION {
            PVOID  Section;                            // 0x00, 0x00
            PVOID  MappedBase;                         // 0x04, 0x08
            PVOID  ImageBase;                          // 0x08, 0x10
            ULONG  ImageSize;                          // 0x0C, 0x18
            ULONG  Flags;                              // 0x10, 0x1C
            USHORT LoadOrderIndex;                     // 0x14, 0x20
            USHORT InitOrderIndex;                     // 0x16, 0x22
            USHORT LoadCount;                          // 0x18, 0x24
            USHORT OffsetToFileName;                   // 0x1A, 0x26
            CHAR   FullPathName[0x100];                // 0x1C, 0x28
        } RTL_PROCESS_MODULE_INFORMATION, *PRTL_PROCESS_MODULE_INFORMATION;

        typedef struct _RTL_PROCESS_MODULES {          // x86   x64
            ULONG NumberOfModules;                     // 0x00, 0x00
            RTL_PROCESS_MODULE_INFORMATION Modules[1]; // 0x04, 0x08
        } RTL_PROCESS_MODULES, *PRTL_PROCESS_MODULES;

        sizeof(RTL_PROCESS_MODULE_INFORMATION)         // 0x11C 0x128
        sizeof(RTL_PROCESS_MODULES)                    // 0x120 0x130
  #>
  begin {
    if (($ta = [PSObject].Assembly.GetType(
      'System.Management.Automation.TypeAccelerators'
    ))::Get.Keys -notcontains 'Marshal') {
      [void]$ta::Add('Marshal', [Runtime.InteropServices.Marshal])
    }

    $NtQuerySystemInformation, $ret = [Regex].Assembly.GetType(
      'Microsoft.Win32.NativeMethods'
    ).GetMethod('NtQuerySystemInformation'), 0
  }
  process {
    try {
      $ptr = [Marshal]::AllocHGlobal(1024)
      if ($NtQuerySystemInformation.Invoke($null, (
        $par = [Object[]]@(11, $ptr, 1024, $ret)
      )) -eq 0xC0000004) {
        $ptr = [Marshal]::ReAllocHGlobal($ptr, [IntPtr]$par[3])
        if (($nts = $NtQuerySystemInformation.Invoke(
          $null, @(11, $ptr, $par[3], 0)
        )) -ne 0) {
          throw New-Object InvalidOperationException(
            'NTSTATUS: 0x{0:X}' -f $nts
          )
        }
      }

      $(0..([Marshal]::ReadInt32($ptr) - 1) | ForEach-Object {
        $of = switch ([IntPtr]::Size) {
          4 { @(0x0C, 0x14, 0x11C, $ptr.ToInt32()) }
          8 { @(0x18, 0x20, 0x128, $ptr.ToInt64()) }
        }
      }{
        $image_base = [Marshal]::ReadIntPtr($ptr, $of[0])
        $name_point = [IntPtr]($of[3] + $of[0] + $of[1])

        New-Object PSObject -Property @{
          Address = '0x{0:X}' -f $(switch ([IntPtr]::Size) {
            4 { $image_base.ToInt32() } 8 { $image_base.ToInt64() }
          })
          Size = [Marshal]::ReadInt32($ptr, $of[0] + 0x04)
          ModuleName = [IO.Path]::GetFileName(
            [Marshal]::PtrToStringAnsi($name_point, 256).Split("`0")[0]
          )
        }
        $of[0] += $of[2]
      }) | Select-Object ModuleName, Address, Size | Format-Table -AutoSize
    }
    catch { $_ }
    finally {
      if ($ptr) { [Marshal]::FreeHGlobal($ptr) }
    }
  }
  end { [void]$ta::Remove('Marshal') }
}

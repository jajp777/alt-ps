function Get-VolumeInfo {
  <#
    .SYNOPSIS
        Retrieves information of a disk volume via hybrid technique.
    .DESCRIPTION
        Data of mounted point is taken from registry. Data of creation
        time and serial number of a volume are got via
        NtQueryVolumeInformationFile function.
    .PARAMETER Path
        A path for a file.
    .EXAMPLE
        PS E:\src> Get-VolumeInfo .\file
        
        Drive        : E:\
        SerialNumber : C4A4-607E
        MountedPoint : \??\Volume{2d771d1c-b94d-11e2-8fc8-002163967079}
        CreationTime : 10.04.2014 13:36:50
    .NOTES
        typedef struct _FILE_FS_VOLUME_INFORMATION {
            LARGE_INTEGER VolumeCreationTime; // +0x00
            ULONG         VolumeSerialNumber; // +0x08
            ULONG         VolumeLabelLength;  // +0x0c
            BOOLEAN       SupportsObjects;    // +0x10
            WCHAR         VolumeLabel[1];     // +0x12
        } FILE_FS_VOLUME_INFORMATION, *PFILE_FS_VOLUME_INFORMATION;
  #>
  param(
    [Parameter(Mandatory=$true)]
    [ValidateScript({($script:fi = Get-Item $_)})]
    [String]$Path
  )
  
  begin {
    function private:New-Delegate {
      param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]$Module,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]$Function,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]$Delegate
      )
      
      begin {
        [Object].Assembly.GetType(
          'Microsoft.Win32.Win32Native'
        ).GetMethods([Reflection.BindingFlags]40) |
        Where-Object {
          $_.Name -cmatch '\AGet(ProcA|ModuleH)'
        } | ForEach-Object {
          Set-Variable $_.Name $_
        }
        
        if (($ptr = $GetProcAddress.Invoke($null, @(
          $GetModuleHandle.Invoke($null, @($Module)), $Function
        ))) -eq [IntPtr]::Zero) {
          throw New-Object InvalidOperationException(
            'Could not find specified signature.'
          )
        }
      }
      process { $proto = Invoke-Expression $Delegate }
      end {
        $method = $proto.GetMethod('Invoke')
        
        $returntype = $method.ReturnType
        $paramtypes = $method.GetParameters() |
                    Select-Object -ExpandProperty ParameterType
        
        $holder = New-Object Reflection.Emit.DynamicMethod(
          'Invoke', $returntype, $paramtypes, $proto
        )
        $il = $holder.GetILGenerator()
        0..($paramtypes.Length - 1) | ForEach-Object {
          $il.Emit([Reflection.Emit.OpCodes]::Ldarg, $_)
        }
        
        switch ([IntPtr]::Size) {
          4 { $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4, $ptr.ToInt32()) }
          8 { $il.Emit([Reflection.Emit.OpCodes]::Ldc_I8, $ptr.ToInt64()) }
        }
        $il.EmitCalli(
          [Reflection.Emit.OpCodes]::Calli,
          [Runtime.InteropServices.CallingConvention]::StdCall,
          $returntype, $paramtypes
        )
        $il.Emit([Reflection.Emit.OpCodes]::Ret)
        
        $holder.CreateDelegate($proto)
      }
    }
    
    $NtQueryVolumeInformationFile = New-Delegate ntdll `
      NtQueryVolumeInformationFile (
      '[Func[IntPtr, [Byte[]], IntPtr, Int32, Int32, Int32]]'
    )
    
    $dev = (
      Get-ItemProperty HKLM:\SYSTEM\MountedDevices
    ).PSObject.Properties | Where-Object {
      $_.Value.GetType().FullName -eq 'System.Byte[]'
    } | Select-Object Name, Value
  }
  process {
    $dd = ($dev | Where-Object {
      $_.Name -eq ($d = "\DosDevices\$($fi.PSDrive.Name):")
    }).Value
    
    $vol = ($dev | Where-Object {
      if (!(Compare-Object $_.Value $dd)) {
        $_.Name
      }
    } | Where-Object {$_.Name -ne $d}).Name
    
    try {
      if (($sfh = [Object].Assembly.GetType(
        'Microsoft.Win32.Win32Native'
      ).GetMethod(
        'CreateFile', [Reflection.BindingFlags]40
      ).Invoke($null, @(
        $fi.Fullname, 0x80000000, [IO.FileShare]::Read, $null,
        [IO.FileMode]::Open, 0, [IntPtr]::Zero
      ))).IsInvalid) {
        throw New-Object ComponentModel.Win32Exception(
          [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        )
      }
      
      $isb = New-Object Byte[]([IntPtr]::Size)
      $fvi = [Runtime.InteropServices.Marshal]::AllocHGlobal(24)
      
      if ($NtQueryVolumeInformationFile.Invoke(
        $sfh.DangerousGetHandle(), $isb, $fvi, 24, 1
      ) -ne 0) {
        throw New-Object InvalidOperationException(
          'Could not retrieve volume information.'
        )
      }
      
      New-Object PSObject -Property @{
        Drive = $fi.PSDrive.Root
        MountedPoint = $vol
        SerialNumber = [Regex]::Replace(
          [Runtime.InteropServices.Marshal]::ReadInt32(
            $fvi, 0x08
          ).ToString('X'), '(\w{4})(\w{4})', '$1-$2'
        )
        CreationTime = [DateTime]::FromFileTime(
          [Runtime.InteropServices.Marshal]::ReadInt64($fvi)
        )
      } | Select-Object Drive, SerialNumber, MountedPoint, CreationTime
    }
    catch { $_.Exception }
    finally {
      if ($fvi) { [Runtime.InteropServices.Marshal]::FreeHGlobal($fvi) }
      if ($sfh) { $sfh.Dispose() }
    }
  }
  end {}
}

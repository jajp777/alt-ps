function Get-Streams {
  <#
    .SYNOPSIS
        Reveals NTFS alternative streams.
    .OUTPUTS
        Object[] or nothing if there are no streams.
    .NOTES
        typedef struct _FILE_STREAM_INFORMATION {
          ULONG         NextEntryOffset;      // 0x00
          ULONG         StreamNameLength;     // 0x04
          LARGE_INTEGER StreamSize;           // 0x08
          LARGE_INTEREG StreamAllocationSIze; // 0x10
          WCHAR         StreamName[1];        // 0x18
        } FILE_STREAM_INFORMATION, *PFILE_STREAM_INFORMATION;
  #>
  param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateScript({($script:fi = Get-Item $_ -ea 0)})]
    [String]$Path,
    
    [Parameter(Position=1)]
    [Switch]$Delete
  )
  
  begin {
    function private:New-Delegate {
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
        [Object].Assembly.GetType(
          'Microsoft.Win32.Win32Native'
        ).GetMethods([Reflection.BindingFlags]40) |
        Where-Object {
          $_.Name -cmatch '\AGet(ProcA|ModuleH)'
        } | ForEach-Object {
          Set-Variable $_.Name $_ -Scope Global
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
    
    $CreateFile = New-Delegate kernel32 CreateFileW (
        '[Func[[Byte[]], UInt32, IO.FileShare, IntPtr, ' +
        'IO.FileMode, UInt32, IntPtr, IntPtr]]'
    )
    $NtQueryInformationFile = New-Delegate ntdll NtQueryInformationFile `
                  '[Func[IntPtr, [Byte[]], IntPtr, Int32, Int32, Int32]]'
    
    ('FILE_FLAG_BACKUP_SEMANTICS', 0x02000000), (
      'GENERIC_READ', 0x80000000
    ) | ForEach-Object {
      Set-Variable $_[0] ([BitConverter]::ToUInt32(
        [BitConverter]::GetBytes($_[1]), 0
      ))
    }
    $STATUS_BUFFER_OVERFLOW, $block = 0x80000005, (16 * 1024)
    $FileStreamInformation = 0x00000016
  }
  process {
    try {
      $hndl = $CreateFile.Invoke(
        [Text.Encoding]::Unicode.GetBytes($fi.FullName),
        $GENERIC_READ, [IO.FileShare]::ReadWrite, [IntPtr]::Zero,
        [IO.FileMode]::Open, $FILE_FLAG_BACKUP_SEMANTICS, [IntPtr]::Zero
      )
      
      $isb = New-Object Byte[]([IntPtr]::Size)
      $fsi = [Runtime.InteropServices.Marshal]::AllocHGlobal($block)
      $nts = $STATUS_BUFFER_OVERFLOW
      
      while ($nts -eq $STATUS_BUFFER_OVERFLOW) {
        if (($nts = $NtQueryInformationFile.Invoke(
          $hndl, $isb, $fsi, $block, $FileStreamInformation
        )) -eq $STATUS_BUFFER_OVERFLOW) {
          $fsi = [Runtime.InteropServices.Marshal]::ReAllocHGlobal(
            $fsi, [IntPtr]($block *= 2)
          )
        }
        else { break }
      }
      
      if ($nts -ne 0) {
        throw New-Object InvalidOperationException(
          'Could not retrieve streams of the specified object.'
        )
      }
      
      $tmp = $fsi
      while ($true) {
        $del = $false
        # NextEntryOffset      - offset 0x00
        $neo = [Runtime.InteropServices.Marshal]::ReadInt32($tmp)
        # StreamNameLength     - offset 0x04
        $snl = [Runtime.InteropServices.Marshal]::ReadInt32($tmp, 0x04)
        # StreamSize           - offset 0x08
        $ssz = [Runtime.InteropServices.Marshal]::ReadInt64($tmp, 0x08)
        # StreamAllocationSize - offset 0x10
        $sas = [Runtime.InteropServices.Marshal]::ReadInt64($tmp, 0x10)
        # StreamName           - offste 0x18
        $mov = switch ([IntPtr]::Size) { 4 {$tmp.ToInt32()} 8 {$tmp.ToInt64()} }
        $itm = [Runtime.InteropServices.Marshal]::PtrToStringUni(
          [IntPtr]($mov + 0x18), $snl / 2
        )
        
        if (!$itm.Equals('::$DATA')) {
          if ($Delete) {
            $del = [Object].Assembly.GetType(
              'Microsoft.Win32.Win32Native'
            ).GetMethod(
              'DeleteFile', [Reflection.BindingFlags]40
            ).Invoke($null, @($fi.FullName + $itm))
          }
          
          New-Object PSObject -Property @{
            Path = $fi.FullName
            IsFile = !$fi.PSIsContainer
            Stream = $itm
            Size = $ssz
            AllocationSize = $sas
            Deleted = $del
          } | Select-Object Path, IsFile, Stream, Size, AllocationSize, Deleted
        }
        
        if ($neo -eq 0) { break }
        $tmp = [IntPtr]($mov + $neo)
      }
    }
    catch {}
    finally {
      if ($fsi) { [Runtime.InteropServices.Marshal]::FreeHGlobal($fsi) }
      if ($hndl) {
        [void][Object].Assembly.GetType(
          'Microsoft.Win32.Win32Native'
        ).GetMethod(
          'CloseHandle', [Reflection.BindingFlags]40
        ).Invoke($null, @($hndl))
      }
    }
  }
  end {}
}

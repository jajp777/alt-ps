function Get-CpuFrequency {
  <#
    .SYNOPSIS
        Retrieves CPUs frequiensies.
    .NOTES
        typedef _SYSTEM_BASIC_INFORMATION {
            BYTE Reserved[43];
            BYTE NumberOfProcessors; // +0x28
        } SYSTEM_BASIC_INFORMATION, *PSYSTEM_BASIC_INFORMATION;
        
        typedef _PROCESSOR_POWER_INFORMATION {
            ULONG Number;            // +0x00
            ULONG MaxMhz;            // +0x04
            ULONG CurrentMhz;        // +0x08
            ULONG MhzLimit;          // +0x0c
            ULONG MaxIdleState;      // +0x10
            ULONG CurrentIdleState;  // +0x14
        } PROCESSOR_POWER_INFORMATION, *PPROCESSOR_POWER_INFORMATION;
        
        SystemBasicInformation = 0
        ProcessorInformation = 11
  #>
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
    
    $NtQuerySystemInformation = New-Delegate ntdll NtQuerySystemInformation `
                              '[Func[Int32, IntPtr, Int32, [Byte[]], Int32]]'
    $NtPowerInformation = New-Delegate ntdll NtPowerInformation `
                       '[Func[Int32, IntPtr, Int32, [Byte[]], Int32, Int32]]'
  }
  process {
    try {
      # sizeof(SYSTEM_BASIC_INFORMATION) = 44
      $sbi = [Runtime.InteropServices.Marshal]::AllocHGlobal(44)
      
      if ($NtQuerySystemInformation.Invoke(0, $sbi, 44, $null) -ne 0) {
        throw New-Object InvalidOperationException(
          'Could not retrieve number of processors.'
        )
      }
      # NumberOfProcessors
      $nop = [Runtime.InteropServices.Marshal]::ReadByte($sbi, 0x28)
      # sizeof(PROCESSOR_POWER_INFORMATION) = 24
      $len = 24 * $nop # correct buffer size
      $buf = New-Object Byte[]($len)
      if ($NtPowerInformation.Invoke(11, [IntPtr]::Zero, 0, $buf, $len) -ne 0) {
        throw New-Object InvalidOperationException(
          'Could not retrieve processor power information.'
        )
      }
      # getting PROCESSOR_POWER_INFORMATION for each processor
      $j = 0
      for ($i = 0; $i -lt $nop; $i++) {
        [Byte[]]$tmp = $buf[$j..($j + 23)]
        $gch = [Runtime.InteropServices.GCHandle]::Alloc($tmp, 'Pinned')
        $ptr = $gch.AddrOfPinnedObject()
        New-Object PSObject -Property @{
          Number = [Runtime.InteropServices.Marshal]::ReadInt32($ptr)
          MaxMhz = [Runtime.InteropServices.Marshal]::ReadInt32($ptr, 0x04)
          CurrentMhz = [Runtime.InteropServices.Marshal]::ReadInt32($ptr, 0x08)
          MhzLimit = [Runtime.InteropServices.Marshal]::ReadInt32($ptr, 0x0c)
          MaxIdleState = [Runtime.InteropServices.Marshal]::ReadInt32($ptr, 0x10)
          CurrentIdleState = [Runtime.InteropServices.Marshal]::ReadInt32($ptr, 0x14)
        } |
        Select-Object Number, MaxMhz, CurrentMhz, MhzLimit, MaxIdleState, CurrentIdleState
        $gch.Free()
        
        $j += 24
      }
    }
    catch { $_.Exception }
    finally {
      if ($sbi) { [Runtime.InteropServices.Marshal]::FreeHGlobal($sbi) }
    }
  }
  end {}
}

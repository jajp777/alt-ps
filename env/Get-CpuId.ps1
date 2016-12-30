function Get-CpuId {
  <#
    .SYNOPSIS
        Queries the CPU for information about its type.
    .NOTES
        Author: greg zakharov
  #>
  begin {
    @(
      [Runtime.InteropServices.CallingConvention],
      [Runtime.InteropServices.GCHandle],
      [Runtime.InteropServices.Marshal],
      [Reflection.Emit.OpCodes]
    ) | ForEach-Object {
      $keys = ($ta = [PSObject].Assembly.GetType(
        'System.Management.Automation.TypeAccelerators'
      ))::Get.Keys
      $collect = @()
    }{
      if ($keys -notcontains $_.Name) { $ta::Add($_.Name, $_) }
      $collect += $_.Name
    } # accelerators
    
    function private:Get-ProcAddress {
      param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String]$Module,
        
        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String[]]$Function
      )
      
      begin {
        [Object].Assembly.GetType(
          'Microsoft.Win32.Win32Native'
        ).GetMethods(
          [Reflection.BindingFlags]40
        ) | Where-Object {
          $_.Name -cmatch '\AGet(ProcA|ModuleH)'
        } | ForEach-Object {
          Set-Variable $_.Name $_
        }
      }
      process {}
      end {
        if (($ptr = $GetModuleHandle.Invoke(
          $null, @($Module)
        )) -eq [IntPtr]::Zero) {
          throw New-Object InvalidOperationException(
            'Could not find specified module.'
          )
        }
        
        $Function | ForEach-Object {$ret = @{}}{
          $ret[$_] = $GetProcAddress.Invoke(
            $null, @($ptr, [String]$_)
          )
        }{$ret}
      }
    } # get-ProcAddress
    
    function private:New-Delegate {
      param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateScript({$_ -ne [IntPtr]::Zero})]
        [IntPtr]$ProcAddress,
        
        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [Type]$Prototype,
        
        [Parameter(Position=2)]
        [ValidateNotNullOrEmpty()]
        [CallingConvention]$CallingConvention = 'StdCall'
      )
      
      $method = $Prototype.GetMethod('Invoke')
      
      $returntype = $method.ReturnType
      $paramtypes = $method.GetParameters() |
                   Select-Object -ExpandProperty ParameterType
      
      $holder = New-Object Reflection.Emit.DynamicMethod(
        'Invoke', $returntype, $(
          if (!$paramtypes) { $null } else { $paramtypes }
        ), $Prototype
      )
      $il = $holder.GetILGenerator()
      if ($paramtypes) {
        0..($paramtypes.Length - 1) | ForEach-Object {
          $il.Emit([OpCodes]::Ldarg, $_)
        }
      }
      
      switch ([IntPtr]::Size) {
        4 { $il.Emit([OpCodes]::Ldc_I4, $ProcAddress.ToInt32()) }
        8 { $il.Emit([OpCodes]::Ldc_I8, $ProcAddress.ToInt64()) }
      }
      $il.EmitCalli(
        [OpCodes]::Calli, $CallingConvention, $returntype,
        $(if (!$paramtypes) { $null } else { $paramtypes })
      )
      $il.Emit([OpCodes]::Ret)
      
      $holder.CreateDelegate($Prototype)
    } # New-Delegate
    
    function private:Get-Blocks {
      param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [Byte[]]$Bytes,
        
        [Parameter()]
        [Switch]$AsInteger,
        
        [Parameter()]
        [Switch]$AsString
      )
      
      $reg = @{
        eax = $Bytes[0..3]
        ebx = $Bytes[4..7]
        ecx = $Bytes[8..11]
        edx = $Bytes[12..15]
      }
      
      if ($AsInteger) {
        $reg.Keys | ForEach-Object {$num = @{}}{
          $num[$_] = [BitConverter]::ToInt32($reg[$_], 0)
        }
        $reg = $num
      }
      
      if ($AsString) {
        $reg.Keys | ForEach-Object {$str = @{}}{
          $str[$_] = -join [Char[]]$reg[$_]
        }
        $reg = $str
      }
      
      $reg
    } # Get-Blocks
    
    # helper function for compatibility with PS v2
    function private:Set-Shift {
      param(
        [Parameter(Position=0)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('Left', 'Right')]
        [String]$Direction = 'Right',
        
        [Parameter(Position=1)]
        [ValidateNotNull()]
        [Object]$Type = [Int32]
      )
      
      @(
        'Ldarg_0'
        'Ldarg_1'
        'Ldc_I4_S, 31'
        'And'
        $(if ($Direction -eq 'Right') { 'Shr' } else { 'Shl' })
        'Ret'
      ) | ForEach-Object {
        $def = New-Object Reflection.Emit.DynamicMethod(
          $Direction, $Type, @($Type, $Type)
        )
        $il = $def.GetILGenerator()
      }{
        if ($_ -notmatch ',') { $il.Emit([OpCodes]::$_) }
        else {
          $il.Emit(
            [OpCodes]::(($$ = $_.Split(','))[0]), ($$[1].Trim() -as $Type)
        )}
      }
      
      $def.CreateDelegate((
        Invoke-Expression "[Func[$($Type.Name), $($Type.Name), $($Type.Name)]]"
      ))
    } # Invoke-Shift
    
    $kernel32 = Get-ProcAddress kernel32 ('VirtualAlloc', 'VirtualFree')
    ($sig = @{
      VirtualAlloc = [Func[IntPtr, UIntPtr, UInt32, UInt32, IntPtr]]
      VirtualFree  = [Func[IntPtr, UIntPtr, UInt32, Boolean]]
    }).Keys | ForEach-Object {
      Set-Variable $_ (New-Delegate $kernel32.$_ $sig[$_])
    }
    
    [Byte[]]$bytes = switch ([IntPtr]::Size) {
      4 {
        0x55,                   #push  ebp
        0x8B, 0xEC,             #mov   ebp,  esp
        0x53,                   #push  ebx
        0x57,                   #push  edi
        0x8B, 0x45, 0x08,       #mov   eax,  dword ptr[ebp+8]
        0x0F, 0xA2,             #cpuid
        0x8B, 0x7D, 0x0C,       #mov   edi,  dword ptr[ebp+12]
        0x89, 0x07,             #mov   dword ptr[edi+0],  eax
        0x89, 0x5F, 0x04,       #mov   dword ptr[edi+4],  ebx
        0x89, 0x4F, 0x08,       #mov   dword ptr[edi+8],  ecx
        0x89, 0x57, 0x0C,       #mov   dword ptr[edi+12], edx
        0x5F,                   #pop   edi
        0x5B,                   #pop   ebx
        0x8B, 0xE5,             #mov   esp,  ebp
        0x5D,                   #pop   ebp
        0xC3                    #ret
      }
      8 {
        0x53,                   #push  rbx
        0x49, 0x89, 0xD0,       #mov   r8,  rdx
        0x89, 0xC8,             #mov   eax, ecx
        0x0F, 0xA2,             #cpuid
        0x41, 0x89, 0x40, 0x00, #mov   dword ptr[r8+0],  eax
        0x41, 0x89, 0x58, 0x04, #mov   dword ptr[r8+4],  ebx
        0x41, 0x89, 0x48, 0x08, #mov   dword ptr[r8+8],  ecx
        0x41, 0x89, 0x50, 0x0C, #mov   dword ptr[r8+12], edx
        0x5B,                   #pop   rbx
        0xC3                    #ret
      }
    }
    
    $features = @{}
  }
  process {
    $func = $ExecutionContext.SessionState.InvokeCommand.GetCommand(
      'New-Delegate', [Management.Automation.CommandTypes]::Function
    ).ScriptBlock
    $shr = Set-Shift
    
    try {
      $ptr = $VirtualAlloc.Invoke(
        [IntPtr]::Zero, (New-Object UIntPtr($bytes.Length)),
        (0x1000 -bor 0x2000), 0x40
      )
      
      $cpuid = {
        param([Int32]$Level, [Byte[]]$Bytes)
        
        $func.Invoke(
          $ptr, [Action[Int32, [Byte[]]]], 'Cdecl'
        )[0].Invoke($Level, $Bytes)
      }
      
      [Marshal]::Copy($bytes, 0, $ptr, $bytes.Length)
      [Byte[]]$buf = New-Object Byte[](16)
      $cpuid.Invoke(0, $buf)
      $vendor = "$(( # vendor string
        $str = Get-Blocks $buf -AsString
      ).ebx)$($str.edx)$($str.ecx)"
      # low leaves
      $ids = (Get-Blocks $buf -AsInteger).eax
      $low = @()
      for ($i = 0; $i -le $ids; $i++) {
        $cpuid.Invoke($i, $buf)
        
        if ($i -eq 1) {
          $reg = Get-Blocks $buf -AsInteger
          
          $stepping = $reg.eax -band 0xF
          $model    = $shr.Invoke($reg.eax, 4) -band 0xF
          $family   = $shr.Invoke($reg.eax, 8) -band 0xF
          $logiccpu = $shr.Invoke($reg.ebx, 16) -band 0xFF
          
          $features['fpu']          = $reg.edx -band 0x00000001
          $features['vme']          = $reg.edx -band 0x00000002
          $features['de']           = $reg.edx -band 0x00000004
          $features['pse']          = $reg.edx -band 0x00000008
          $features['tsc']          = $reg.edx -band 0x00000010
          $features['msr']          = $reg.edx -band 0x00000020
          $features['pae']          = $reg.edx -band 0x00000040
          $features['mce']          = $reg.edx -band 0x00000080
          $features['cx8']          = $reg.edx -band 0x00000100
          $features['apic']         = $reg.edx -band 0x00000200
          $features['sep']          = $reg.edx -band 0x00000800
          $features['mtrr']         = $reg.edx -band 0x00001000
          $features['pge']          = $reg.edx -band 0x00002000
          $features['mca']          = $reg.edx -band 0x00004000
          $features['cmov']         = $reg.edx -band 0x00008000
          $features['pat']          = $reg.edx -band 0x00010000
          $features['pse36']        = $reg.edx -band 0x00020000
          $features['psn']          = $reg.edx -band 0x00040000
          $features['clflush']      = $reg.edx -band 0x00080000
          $features['ds']           = $reg.edx -band 0x00200000
          $features['acpi']         = $reg.edx -band 0x00400000
          $features['mmx']          = $reg.edx -band 0x00800000
          $features['fxsr']         = $reg.edx -band 0x01000000
          $features['sse']          = $reg.edx -band 0x02000000
          $features['sse2']         = $reg.edx -band 0x04000000
          $features['ss']           = $reg.edx -band 0x08000000
          $features['htt']          = $reg.edx -band 0x10000000
          $features['tm']           = $reg.edx -band 0x20000000
          $features['ia64']         = $reg.edx -band 0x40000000
          $features['pbe']          = $reg.edx -band 0x80000000
          
          $features['sse3']         = $reg.ecx -band 0x00000001
          $features['pclmulqdq']    = $reg.ecx -band 0x00000002
          $features['dtes64']       = $reg.ecx -band 0x00000004
          $features['monitor']      = $reg.ecx -band 0x00000008
          $features['ds_cpl']       = $reg.ecx -band 0x00000010
          $features['vmx']          = $reg.ecx -band 0x00000020
          $features['smx']          = $reg.ecx -band 0x00000040
          $features['est']          = $reg.ecx -band 0x00000080
          $features['tm2']          = $reg.ecx -band 0x00000100
          $features['ssse3']        = $reg.ecx -band 0x00000200
          $features['cntx_id']      = $reg.ecx -band 0x00000400
          $features['sdbg']         = $reg.ecx -band 0x00000800
          $features['fma']          = $reg.ecx -band 0x00001000
          $features['cx16']         = $reg.ecx -band 0x00002000
          $features['xtpr']         = $reg.ecx -band 0x00004000
          $features['pdcm']         = $reg.ecx -band 0x00008000
          $features['pcid']         = $reg.ecx -band 0x00020000
          $features['dca']          = $reg.ecx -band 0x00040000
          $features['sse4_1']       = $reg.ecx -band 0x00080000
          $features['sse4_2']       = $reg.ecx -band 0x00100000
          $features['x2apic']       = $reg.ecx -band 0x00200000
          $features['movbe']        = $reg.ecx -band 0x00400000
          $features['popcnt']       = $reg.ecx -band 0x00800000
          $features['tsc_deadline'] = $reg.ecx -band 0x01000000
          $features['aes']          = $reg.ecx -band 0x02000000
          $features['xsave']        = $reg.ecx -band 0x04000000
          $features['osxsave']      = $reg.ecx -band 0x08000000
          $features['avx']          = $reg.ecx -band 0x10000000
          $features['f16c']         = $reg.ecx -band 0x20000000
          $features['rdrnd']        = $reg.ecx -band 0x40000000
          $features['hypervisor']   = $reg.ecx -band 0x80000000
        }
        
        $leave = New-Object PSObject -Property (Get-Blocks $buf -AsInteger)
        $low += $leave
      }
      # high leaves
      $cpuid.Invoke(0x80000000, $buf)
      $ids = (Get-Blocks $buf -AsInteger).eax
      $top = @()
      $name = '' # brand string
      for ($i = 0x80000000; $i -le $ids; $i++) {
        $cpuid.Invoke($i, $buf)
        
        if ($i -eq 0x80000001) {
          $reg = Get-Blocks $buf -AsInteger
          
          $features['syscall']       = $reg.edx -band 0x00000800
          $features['mp']            = $reg.edx -band 0x00080000
          $features['nx']            = $reg.edx -band 0x00100000
          $features['mmxext']        = $reg.edx -band 0x00400000
          $features['fxsr_opt']      = $reg.edx -band 0x02000000
          $features['pdpe1gb']       = $reg.edx -band 0x04000000
          $features['rdtscp']        = $reg.edx -band 0x08000000
          $features['lm']            = $reg.edx -band 0x20000000
          $features['3dnowext']      = $reg.edx -band 0x40000000
          $features['3dnow']         = $reg.edx -band 0x80000000
          
          $features['lahf_lm']       = $reg.ecx -band 0x00000001
          $features['cmp_legacy']    = $reg.ecx -band 0x00000002
          $features['svm']           = $reg.ecx -band 0x00000004
          $features['extapic']       = $reg.ecx -band 0x00000008
          $features['cr8_legacy']    = $reg.ecx -band 0x00000010
          $features['abm']           = $reg.ecx -band 0x00000020
          $features['sse4a']         = $reg.ecx -band 0x00000040
          $features['misalingsse']   = $reg.ecx -band 0x00000080
          $features['3dnowprefetch'] = $reg.ecx -band 0x00000100
          $features['osvw']          = $reg.ecx -band 0x00000200
          $features['ibs']           = $reg.ecx -band 0x00000400
          $features['xop']           = $reg.ecx -band 0x00000800
          $features['skinit']        = $reg.ecx -band 0x00001000
          $features['wdt']           = $reg.ecx -band 0x00002000
          $features['lwp']           = $reg.ecx -band 0x00008000
          $features['fma4']          = $reg.ecx -band 0x00010000
          $features['tce']           = $reg.ecx -band 0x00020000
          $features['nodeid_msr']    = $reg.ecx -band 0x00080000
          $features['tbm']           = $reg.ecx -band 0x00200000
          $features['topoext']       = $reg.ecx -band 0x00400000
          $features['perfctr_core']  = $reg.ecx -band 0x00800000
          $features['perfctr_nb']    = $reg.ecx -band 0x01000000
          $features['dbx']           = $reg.ecx -band 0x04000000
          $features['perftsc']       = $reg.ecx -band 0x08000000
          $features['pcx_l2i']       = $reg.ecx -band 0x10000000
        }
        
        if ($i -eq 0x80000002 -or $i -eq 0x80000003 -or $i -eq 0x80000004) {
          $name += "$((
            $reg = Get-Blocks $buf -AsString
          ).eax)$($reg.ebx)$($reg.ecx)$($reg.edx)"
        }
        
        $leave = New-Object PSObject -Property (Get-Blocks $buf -AsInteger)
        $top += $leave
      }
      
      $cpuid = New-Object PSObject -Property @{
        Vendor          = $vendor
        Name            = $name.Trim()
        SteppingId      = $stepping
        Model           = $model
        Family          = $family
        LogicalCPUCount = $logiccpu
        Features        = $features.Keys | ForEach-Object {
          if ($features[$_]) { $_ }
        } | Sort-Object
        LowLeaves       = $low
        HighLeaves      = $top
      } | Select-Object (
        'Vendor', 'Name', 'SteppingId', 'Model', 'Family',
        'LogicalCPUCount', 'Features', 'LowLeaves', 'HighLeaves'
      )
    }
    catch { $_ }
    finally {
      if ($ptr) { [void]$VirtualFree.Invoke($ptr, [UIntPtr]::Zero, 0x8000) }
    }
  }
  end {
    $cpuid
    $collect | ForEach-Object { [void]$ta::Remove($_) }
  }
}

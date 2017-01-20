function Import-FromDll {
  <#
    .SYNOPSIS
        Allows to invoke some WinAPI functions without using Add-Type
        cmdlet.
    .DESCRIPTION
        This is possible due to reflection and Func and Action delegates.
        Import-FromDll uses GetModuleHandle and GetProcAddress functions
        stored into Microsoft.Win32.Win32Native type of mscorlib.dll
    .PARAMETER Module
        Library module name (DLL). Note that it should be currently loaded
        by host, to check this:
        
       (ps -Is $PID).Modules | ? {$_.FileName -notmatch '(\.net|assembly)'}
    .PARAMETER Signature
        Signatures storage which presented as a hashtable.
    .EXAMPLE
        $kernel32 = Import-FromDll kernel32 -Signature @{
          CreateHardLinkW = [Func[[Byte[]], [Byte[]], IntPtr, Boolean]]
          GetCurrentProcessId = [Func[Int32]]
        }
        
        $kernel32.GetCurrentProcessId.Invoke()
        This will return value which is equaled $PID variable.
        
        $kernel32.CreateHardLinkW.Invoke(
          [Text.Encoding]::Unicode.GetBytes('E:\to\target.ext'),
          [Text.Encoding]::Unicode.GetBytes('E:\from\source.ext'),
          [IntPtr]::Zero
        )
        Establishes a hard link between an existing file and a new file.
    .OUTPUTS
        Hashtable
    .NOTES
        Author: greg zakharov
  #>
  param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateNotNullOrEmpty()]
    [String]$Module,
    
    [Parameter(Mandatory=$true, Position=1)]
    [ValidateNotNull()]
    [Hashtable]$Signature
  )
  
  begin {
    function script:Get-ProcAddress {
      [OutputType([Hashtable])]
      param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String]$Module,
        
        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNull()]
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
        
        if (($mod = $GetModuleHandle.Invoke(
          $null, @($Module)
        )) -eq [IntPtr]::Zero) {
          throw New-Object InvalidOperationException(
            'Could not find specified module.'
          )
        }
      }
      process {}
      end {
        $table = @{}
        foreach ($f in $Function) {
          if (($$ = $GetProcAddress.Invoke(
            $null, @($mod, $f)
          )) -ne [IntPtr]::Zero) {
            $table.$f = $$
          }
        }
        $table
      }
    }
    
    function private:New-Delegate {
      param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateScript({$_ -ne [IntPtr]::Zero})]
        [IntPtr]$ProcAddress,
        
        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNull()]
        [Type]$Prototype,
        
        [Parameter(Position=2)]
        [ValidateNotNullOrEmpty()]
        [Runtime.InteropServices.CallingConvention]
        $CallingConvention = 'StdCall'
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
          $il.Emit([Reflection.Emit.OpCodes]::Ldarg, $_)
        }
      }
      
      switch ([IntPtr]::Size) {
        4 { $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4, $ProcAddress.ToInt32()) }
        8 { $il.Emit([Reflection.Emit.OpCodes]::Ldc_I8, $ProcAddress.ToInt64()) }
      }
      $il.EmitCalli(
        [Reflection.Emit.OpCodes]::Calli, $CallingConvention, $returntype,
        $(if (!$paramtypes) { $null } else { $paramtypes })
      )
      $il.Emit([Reflection.Emit.OpCodes]::Ret)
      
      $holder.CreateDelegate($Prototype)
    }
  }
  process {}
  end {
    $scope, $fname = @{}, (Get-ProcAddress $Module $Signature.Keys)
    foreach ($key in $fname.Keys) {
      $scope[$key] = New-Delegate $fname[$key] $Signature[$key]
    }
    $scope
  }
}

function Get-CpuFrequency {
  <#
    .SYNOPSIS
        Retrieves CPUs frequensies.
    .NOTES
        Author: greg zakharov
  #>
  begin {
    $ntdll = Import-FromDll ntdll -Signature @{
      NtPowerInformation = [Func[Int32, IntPtr, Int32, [Byte[]], Int32, Int32]]
      NtQuerySystemInformation = [Func[Int32, IntPtr, Int32, [Byte[]], Int32]]
    }
  }
  process {
    try {
      # sizeof(SYSTEM_BASIC_INFORMATION) = 44
      $sbi = [Runtime.InteropServices.Marshal]::AllocHGlobal(44)

      if ($ntdll.NtQuerySystemInformation.Invoke(0, $sbi, 44, $null) -ne 0) {
        throw New-Object InvalidOperationException(
          'Could not retrive number of processors.'
        )
      }
      # NumberOfProcessors
      $nop = [Runtime.InteropServices.Marshal]::ReadByte($sbi, 0x28)
      # sizeof(PROCESSOR_POWER_INFORMATION) = 24
      $len = 24 * $nop # correct buffer size
      $buf = New-Object Byte[]($len)
      if ($ntdll.NtPowerInformation.Invoke(11, [IntPtr]::Zero, 0, $buf, $len) -ne 0) {
        Remove-Variable buf
        throw New-Object InvalidOperationException(
          'Could not retrieve processor(s) power information.'
        )
      }
    }
    catch { Write-Verbose $_ }
    finally {
      if ($sbi) { [Runtime.InteropServices.Marshal]::FreeHGlobal($sbi) }
    }
  }
  end {
    if (!$buf) { return }
    # getting PROCESSOR_POWER_INFORMATION for each processor
    $j = 0
    for ($i = 0; $i -lt $nop; $i++) {
      [Byte[]]$tmp = $buf[$j..($j + 23)]
      $gch = [Runtime.InteropServices.GCHandle]::Alloc($tmp, 'Pinned')
      $ptr = $gch.AddrOfPinnedObject()
      New-Object PSObject -Property @{
        Number           = [Runtime.InteropServices.Marshal]::ReadInt32($ptr)
        MaxMhz           = [Runtime.InteropServices.Marshal]::ReadInt32($ptr, 0x04)
        CurrentMhz       = [Runtime.InteropServices.Marshal]::ReadInt32($ptr, 0x08)
        MhzLimit         = [Runtime.InteropServices.Marshal]::ReadInt32($ptr, 0x0c)
        MaxIdleState     = [Runtime.InteropServices.Marshal]::ReadInt32($ptr, 0x10)
        CurrentIdleState = [Runtime.InteropServices.Marshal]::ReadInt32($ptr, 0x14)
      } |
      Select-Object Number, MaxMhz, CurrentMhz, MhzLimit, MaxIdleState, CurrentIdleState
      $gch.Free()

      $j += 24
    }
  }
}

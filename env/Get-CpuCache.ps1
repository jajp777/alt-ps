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

function Get-CpuCache {
  <#
    .SYNOPSIS
        Retrieves information about processor cache information.
    .NOTES
        Author: greg zakharov
  #>
  begin {
    if (($clr = $PSVersionTable.CLRVersion.Major) -ge 4) {
      $ntdll = Import-FromDll ntdll @{
        NtQuerySystemInformation = [Func[Int32, IntPtr, Int32, [Byte[]], Int32]]
      }
    }
    else {
      $kernel32 = Import-FromDll kernel32 @{
        GetLogicalProcessorInformation = [Func[IntPtr, [Byte[]], Boolean]]
      }
    }
  }
  process {
    [Byte[]]$ret = New-Object Byte[](4)

    try {
      if ($clr -ge 4) {
        $sz = 0x18 # sizeof(SYSTEM_LOGICAL_PROCESSOR_INFORMATION)
        $ptr = [Runtime.InteropServices.Marshal]::AllocHGlobal($sz)
        if ($ntdll.NtQuerySystemInformation.Invoke(73, $ptr, $sz, $ret) -eq 0xC0000004) {
          $sz = [BitConverter]::ToInt32($ret, 0)
          $ptr = [Runtime.InteropServices.Marshal]::ReAllocHGlobal($ptr, [IntPtr]$sz)

          if ($ntdll.NtQuerySystemInformation.Invoke(73, $ptr, $sz, $null) -ne 0) {
            throw New-Object InvalidOperationException(
              'Could not retrieve CPU cache information.'
            )
          }
        }
      }
      else {
        if (!$kernel32.GetLogicalProcessorInformation.Invoke([IntPtr]::Zero, $ret)) {
          if (($sz = [BitConverter]::ToInt32($ret, 0)) -eq 0) {
            throw New-Object InvalidOperationException(
              'Could not invoke GetLogicalProcessorInformation delegate.'
            )
          }

          $ptr = [Runtime.InteropServices.Marshal]::AllocHGlobal($sz)
          if (!$kernel32.GetLogicalProcessorInformation.Invoke($ptr, $ret)) {
            throw New-Object InvalidOperationException(
              'Could not retrieve CPU cache information.'
            )
          }
        }
      }

      $tmp = $ptr
      $CACHE_DESCRIPTOR = for ($i = 0; $i -lt $sz; $i += $sz / 0x18) {
        if ([Runtime.InteropServices.Marshal]::ReadInt32($tmp, 4) -eq 2) { # cache data
          [Byte[]]$bytes = 0..11 | ForEach-Object {
            $ofb = 8
            $CACHE_TYPE = @('CacheUnified', 'CacheInstruction', 'CacheData', 'CacheTrace')
          }{
            [Runtime.InteropServices.Marshal]::ReadByte($tmp, $ofb)
            $ofb++
          }

          New-Object PSObject -Property @{
            Level = $bytes[0]
            Associativity = $bytes[1]
            LineSize = [BitConverter]::ToInt16($bytes[2..3], 0)
            Size = [BitConverter]::ToInt32($bytes[4..7], 0)
            Type = $CACHE_TYPE[[BitConverter]::ToInt32($bytes[8..15], 0)]
          }
        }
        $tmp = [IntPtr]($tmp.ToInt32() + 0x18)
      }
    }
    catch { Write-Verbose $_ }
    finally {
      if ($ptr) { [Runtime.InteropServices.Marshal]::FreeHGlobal($ptr) }
    }
  }
  end {
    if ($CACHE_DESCRIPTOR) {
      $CACHE_DESCRIPTOR | Select-Object Type, Level, @{
        N='Size(KB)';E={$_.Size / 1Kb}
      }, Associativity, LineSize | Format-Table -AutoSize
    }
  }
}

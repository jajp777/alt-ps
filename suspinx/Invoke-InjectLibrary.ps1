#requires -version 5
function Import-FromDll {
  <#
    .SYNOPSIS
        Helper function for creation a scope of delegates.
    .EXAMPLE
        $kernel32 = Import-FromDll kernel32 -Signature @{
          GetCurrentProcessId = [Func[Int32]]
        }
    .NOTES
        Author: greg zakharov
  #>
  [OutputType([Hashtable])]
  param(
    [Parameter(Mandatory, Position=0)]
    [ValidateNotNullOrEmpty()]
    [String]$Module,
    
    [Parameter(Mandatory, Position=1)]
    [ValidateNotNull()]
    [Hashtable]$Signature
  )
  
  begin {
    function script:Get-ProcAddress {
      [OutputType([Hashtable])]
      param(
        [Parameter(Mandatory, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String]$Module,
        
        [Parameter(Mandatory, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String[]]$Function
      )
      
      begin {
        [Object].Assembly.GetType(
          'Microsoft.Win32.Win32Native'
        ).GetMethods([Reflection.BindingFlags]40).Where{
          $_.Name -cmatch '\AGet(ProcA|ModuleH)'
        }.ForEach{ Set-Variable $_.Name $_ }
        
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
        $adr = @{}
        foreach ($f in $Function) {
          if (($$ = $GetProcAddress.Invoke(
            $null, @($mod, $f)
          )) -ne [IntPtr]::Zero) {
            $adr.$f = $$
          }
        }
        $adr
      }
    }
    
    function private:New-Delegate {
      [OutputType([Type])]
      param(
        [Parameter(Mandatory, Position=0)]
        [ValidateScript({$_ -ne [IntPtr]::Zero})]
        [IntPtr]$ProcAddress,
        
        [Parameter(Mandatory, Position=1)]
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
        (0..($paramtypes.Length - 1)).ForEach{
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

function Invoke-InjectLibrary {
  <#
    .SYNOPSIS
        Injects specified DLL into the target process.
    .EXAMPLE
        Invoke-InjectLibrary $PID -DllPath E:\evil.dll
    .NOTES
        Author: greg zakharov
  #>
  [OutputType([Boolean])]
  param(
    [Parameter(Mandatory, Position=0)]
    [ValidateScript({
       ($script:proc = Get-Process -Id $_ -ea 0) -ne $null
    })]
    [Int32]$Id,

    [Parameter(Mandatory, Position=1)]
    [ValidateScript({Test-Path $_})]
    [String]$DllPath
  )

  begin {
    $kernel32 = Import-FromDll kernel32 -Signature @{
      CloseHandle = [Func[IntPtr, Boolean]]
      CreateRemoteThread = [Func[IntPtr, IntPtr, UInt32, IntPtr, IntPtr, UInt32, [Byte[]], IntPtr]]
      IsWow64Process = [Func[IntPtr, [Byte[]], Boolean]]
      OpenProcess = [Func[UInt32, Boolean, Int32, IntPtr]]
      VirtualAllocEx = [Func[IntPtr, IntPtr, Int32, UInt32, UInt32, IntPtr]]
      VirtualFreeEx = [Func[IntPtr, IntPtr, Int32, UInt32, Boolean]]
      WaitForSingleObject = [Func[IntPtr, UInt32, UInt32]]
      WriteProcessMemory = [Func[IntPtr, IntPtr, [Byte[]], Int32, IntPtr, Boolean]]
    }

    $LoadLibrary = (script:Get-ProcAddress kernel32 LoadLibraryW).LoadLibraryW
    $DllPath = Resolve-Path $DllPath
    $INFINITE = [BitConverter]::ToUInt32([BitConverter]::GetBytes(0xFFFFFFFF), 0)
  }
  process {
    try {
      $fs = [IO.File]::OpenRead($DllPath)
      $br = New-Object IO.BinaryReader($fs)

      $e_magic = $br.ReadUInt16() # MZ
      $fs.Position = 0x3C
      $fs.Position = $br.ReadUInt16()
      $pe_sign = $br.ReadUInt32() # PE\0\0

      if ($e_magic -ne 23117 -and $pe_sign -ne 177744) {
        throw New-Object Exception('Unknown file format.')
      }

      $dll = switch ($br.ReadInt16()) {
        0x014C  { 'x86' }
        0x8664  { 'x64' }
        default { 'nil' }
      }
    }
    catch { Write-Verbose $_ }
    finally {
      if ($br) { $br.Dispose() }
      if ($fs) { $fs.Dispose() }
    }
  }
  end {
    if (!$dll -or $dll -eq 'nil') {
      Write-Error 'selected DLL has unrecognized format.'
      return
    }

    $x64proc = New-Object Byte[](4)
    [void]$kernel32.IsWow64Process.Invoke($script:proc.Handle, $x64proc)
    if ([BitConverter]::ToBoolean($x64proc, 0)) {
      if ($dll -ne 'x64') {
        Write-Error 'could not inject 32-bit DLL into 64-bit process.'
        return
      }
    }
    else {
      if ($dll -ne 'x86') {
        Write-Error 'could not inject 64-bit DLL into 32-bit process.'
        return
      }
    }

    $sz = ([IO.FileInfo]$DllPath).Length # size of the region of memory to allocate
    if (($hndl = $kernel32.OpenProcess.Invoke(0x42A, $false, $script:proc.Id)) -ne [IntPtr]-1) {
      Write-Verbose "OpenProcess returns $hndl"
      if (($vmem = $kernel32.VirtualAllocEx.Invoke($hndl, [IntPtr]::Zero, $sz, 0x3000, 4)
      ) -ne [IntPtr]::Zero) { # commits a region of memory within the virtual address space
        Write-Verbose "VirtualAllocEx returns $vmem"
        $bytes = [Text.Encoding]::Unicode.GetBytes($DllPath)
        $res = $kernel32.WriteProcessMemory.Invoke($hndl, $vmem, $bytes, $sz, [IntPtr]::Zero)
        Write-Verbose "WriteProcessMemory returns $res"
        if ($res) {
          if (($thrd = $kernel32.CreateRemoteThread.Invoke(
            $hndl, [IntPtr]::Zero, 0, $LoadLibrary, $vmem, 0, $null
          )) -ne [IntPtr]::Zero) {
            Write-Verbose "CreateRemoteThread returns $thrd"
            $res = $kernel32.WaitForSingleObject.Invoke($thrd, $INFINITE)
            Write-Verbose "WiatForSingleObject returns $res"
            $res = $kernel32.CloseHandle.Invoke($thrd)
            Write-Verbose "CloseHandle returns $res"
          }
        }
        $res = $kernel32.VirtualFreeEx.Invoke($hndl, $vmem, 0, 0x8000)
        Write-Verbose "VirtualFreeEx returns $res"
      }
      $res = $kernel32.CloseHandle.Invoke($hndl)
      Write-Verbose "CloseHandle returns $res"
    }

    ![String]::IsNullOrEmpty($script:proc.Modules.Where{$_.FileName -eq $DllPath}.FileName)
  }
}

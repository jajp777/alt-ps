function Get-Handles {
  <#
    .SYNOPSIS
        Enumerates handles of the specified process.
    .EXAMPLE
        PS C:\> Get-Handles 3828
    .NOTES
        PROCESS_DUP_HANDLE = 0x40
        STATUS_INFO_LENGTH_MISMATCH = 0xC0000004
        STATUS_SUCCESS = 0x00000000
        
        SystemHandleInformation = 16
        ObjectNameInformation = 1
        ObjectTypeInformation = 2
        
        This script has been written on Win7 x86.
  #>
  param(
    [Parameter(Mandatory=$true)]
    [ValidateScript({($script:proc = Get-Process -Id $_)})]
    [Int32]$Id
  )
  
  begin {
    @(
      [Runtime.InteropServices.Marshal],
      [Runtime.InteropServices.GCHandle],
      [Runtime.InteropServices.CharSet],
      [Runtime.InteropServices.CallingConvention],
      [Reflection.BindingFlags]
    ) | ForEach-Object {
      $keys = ($ta = [PSObject].Assembly.GetType(
        'System.Management.Automation.TypeAccelerators'
      ))::Get.Keys
      $collect = @()
    }{
      if ($keys -notcontains $_.Name) { $ta::Add($_.Name, $_) }
      $collect += $_.Name
    }
    
    function private:New-DllImport {
      param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String]$Module,
        
        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String]$Function,
        
        [Parameter(Mandatory=$true, Position=2)]
        [Type]$ReturnType,
        
        [Parameter(Position=3)]
        [Type[]]$Parameters,
        
        [Parameter()]
        [Switch]$SetLastError,
        
        [Parameter()]
        [CharSet]$CharSet = 'Auto',
        
        [Parameter()]
        [CallingConvention]$CallingConvention = 'WinApi',
        
        [Parameter()]
        [String]$EntryPoint
      )
      
      begin {
        $mod = if (!($m = $ExecutionContext.SessionState.PSVariable.Get(
            'PowerShellDllImport'
        ))) {
          $mb = ([AppDomain]::CurrentDomain.DefineDynamicAssembly(
            (New-Object Reflection.AssemblyName('PowerShellDllImport')), 'Run'
          )).DefineDynamicModule('PowerShellDllImport', $false)
          
          Set-Variable PowerShellDllImport -Value $mb -Option Constant `
                                           -Scope Global -Visibility Private
          $mb # first execution
        }
        else { $m.Value }
      }
      process {}
      end {
        try { $pin = $mod.GetType("${Function}Sig") }
        catch {}
        finally {
          if (!$pin) {
            $pin = $mod.DefineType("${Function}Sig", 'Public, BeforeFieldInit')
            $fun = $pin.DefineMethod(
              $Function, 'Public, Static, PinvokeImpl', $ReturnType, $Parameters
            )
            
            $Parameters | ForEach-Object { $i = 1 }{
              if ($_.IsByRef) { [void]$fun.DefineParameter($i, 'Out', $null) }
              $i++
            }
            
            ($dllimport = [Runtime.InteropServices.DllImportAttribute]).GetFields() |
            Where-Object { $_.Name -cmatch '\A(C|En|S)' } | ForEach-Object {
              Set-Variable "_$($_.Name)" $_
            }
            $ErrorValue = if ($SetLastError) { $true } else { $false }
            $EntryPoint = if ($EntryPoint) { $EntryPoint } else { $Function }
            
            $atr = New-Object Reflection.Emit.CustomAttributeBuilder(
              $dllimport.GetConstructor([String]), $Module, [Reflection.PropertyInfo[]]@(),
              [Object[]]@(), [Reflection.FieldInfo[]]@(
                $_SetLastError, $_CallingConvention, $_CharSet, $_EntryPoint
              ), [Object[]]@(
                $ErrorValue, [CallingConvention]$CallingConvention,
                [CharSet]$CharSet, $EntryPoint
              )
            )
            $fun.SetCustomAttribute($atr)
            
            $pin = $pin.CreateType()
          }
          $pin
        }
      }
    }
    
    function private:Get-PageSize {
      $ret, $page = 0, 0
      
      try {
        $sbi = [Marshal]::AllocHGlobal(44)
        
        if ($s6::NtQuerySystemInformation(0, $sbi, 44, [ref]$ret) -ne 0) {
          throw New-Object InvalidOperationException(
            'Could not retrieve page size.'
          )
        }
        $page = [Marshal]::ReadInt32($sbi, 0x08)
      }
      catch {}
      finally { if ($sbi) { [Marshal]::FreeHGlobal($sbi) } }
      
      $page
    }
    
    function private:Move-Next([IntPtr]$ptr) {
      $hne = 16 # sizeof(SYSTEM_HANDLE_TABLE_ENTRY_INFO), next offset
      $mov = switch ([IntPtr]::Size) { 4 {$ptr.ToInt32()} 8 {$ptr.ToInt64()} }
      [IntPtr]($mov + $hne)
    }
    
    $s1 = New-DllImport kernel32 CloseHandle ([Boolean]) @([IntPtr]) -SetLastError
    $s2 = New-DllImport kernel32 OpenProcess ([IntPtr]) @(
        [UInt32], [Boolean], [Int32]
    ) -SetLastError
    $s3 = New-DllImport kernel32 GetCurrentProcess ([IntPtr]) @() -SetLastError
    $s4 = New-DllImport ntdll NtDuplicateObject ([Int32]) @(
        [IntPtr], [IntPtr], [IntPtr], [IntPtr].MakeByRefType(),
        [UInt32], [UInt32], [UInt32]
    )
    $s5 = New-DllImport ntdll NtQueryObject ([Int32]) @(
        [IntPtr], [UInt32], [IntPtr], [UInt32], [UInt32].MakeByRefType()
    )
    $s6 = New-DllImport ntdll NtQuerySystemInformation ([Int32]) @(
        [UInt32], [IntPtr], [UInt32], [UInt32].MakeByRefType()
    )
    # UNICODE_STRING and its size
    $usz = [Marshal]::SizeOf((
      $UNICODE_STRING = [Activator]::CreateInstance(
        [Object].Assembly.GetType(
          'Microsoft.Win32.Win32Native+UNICODE_STRING'
        )
      )
    ))
  }
  process {
    if (($hndl = $s2::OpenProcess(0x40, $false, $proc.Id)) -eq [IntPtr]::Zero) {
      return
    }
    
    $ret = 0
    $sz = 0x10000 # buffer size
    $page = Get-PageSize
    try {
      # SYSTEM_HANDLE_INFORMATION
      $shi = [Marshal]::AllocHGlobal($sz)
      # getting real buffer size
      while ($s6::NtQuerySystemInformation(
        16, $shi, [UInt32]$sz, [ref]$ret
      ) -eq 0xC0000004) {
        $shi = [Marshal]::ReAllocHGlobal(
          $shi, [IntPtr]($sz *= 2)
        )
      }
      # NumberOfHandles
      $noh = [Marshal]::ReadInt32($shi)
      $mov = switch ([IntPtr]::Size) { 4 {$shi.ToInt32()} 8 {$shi.ToInt64()} }
      # first handle
      $tmp = [IntPtr]($mov + [Marshal]::Sizeof([Type][UInt32]))
      
      $(for ($i = 0; $i -lt $noh; $i++) {
        # SYSTEM_HANDLE_TABLE_ENTRY_INFO
        $hte = New-Object PSObject -Property @{
          UniqueProcessId  = [Marshal]::ReadInt32($tmp)
          ObjectTypeIndex  = [Marshal]::ReadByte($tmp, 0x04)
          HandleAttributes = [Marshal]::ReadByte($tmp, 0x05)
          HandleValue      = [Marshal]::ReadInt16($tmp, 0x06)
          Object           = [Marshal]::ReadIntPtr($tmp, 0x08)
          GrantedAccess    = [Marshal]::ReadInt32($tmp, 0x0C)
        }
        # temporary vars
        [IntPtr]$duple = [IntPtr]::Zero # duplicated handle
        [IntPtr]$obj   = [IntPtr]::Zero # object type
        [IntPtr]$name  = [IntPtr]::Zero # name info
        
        $ret = 0 # flush previous $ret data
        if ($hte.UniqueProcessId -ne $Id) {
          $tmp = Move-Next $tmp
          continue
        }
        # duplicate for query
        if (($nts = $s4::NtDuplicateObject(
          $hndl, [IntPtr]$hte.HandleValue,
          $s3::GetCurrentProcess(), [ref]$duple, 0, 0, 0
        )) -ne 0) {
          $tmp = Move-Next $tmp
          continue
        }
        
        try {
          # getting handle type
          $obj = [Marshal]::AllocHGlobal($page)
          if ($s5::NtQueryObject(
            $duple, 2, $obj, $page, [ref]$ret
          ) -ne 0) { throw New-Object InvalidOperationException }
          
          [Byte[]]$bytes = 0..($usz - 1) | ForEach-Object {$ofb = 0}{
            [Marshal]::ReadByte($obj, $ofb)
            $ofb++
          }
          
          $gch = [GCHandle]::Alloc($bytes, 'Pinned')
          $uni = [Marshal]::PtrToStructure(
            $gch.AddrOfPinnedObject(), [Type]$UNICODE_STRING.GetType()
          )
          $gch.Free()
          $obj_type = $uni.GetType().GetField(
            'Buffer', [BindingFlags]36
          ).GetValue($uni)
          
          if ($hte.GrantedAccess -eq 0x12019F) {
            throw New-Object InvalidOperationException
          }
          # getting handle name
          $ret = 0
          $name = [Marshal]::AllocHGlobal($page)
          if ($s5::NtQueryObject(
            $duple, 1, $name, $page, [ref]$ret
          ) -ne 0) {
            $name = [Marshal]::ReaAllocHGlobal($name, [IntPtr]$ret)
            if ($s5::NtQueryObject(
              $duple, 1, $name, $page, [ref]$ret
            ) -ne 0) { throw New-Object InvalidOperationException }
          }
          
          $uni = [Marshal]::PtrToStructure(
            $name, [Type]$UNICODE_STRING.GetType()
          )
          $obj_name = $uni.GetType().GetField(
            'Buffer', [BindingFlags]36
          ).GetValue($uni)
          # print available data
          if (![String]::IsNullOrEmpty($obj_name)) {
            New-Object PSObject -Property @{
              Handle = '0x{0:X}' -f $hte.HandleValue
              Type   = $obj_type
              Name   = $obj_name
            }
          }
        }
        catch {}
        finally {
          if ($name -ne [IntPtr]::Zero) { [Marshal]::FreeHGlobal($name) }
          if ($obj -ne [IntPtr]::Zero) { [Marshal]::FreeHGlobal($obj) }
        }
        
        [void]$s1::CloseHandle($duple)
        $tmp = Move-Next $tmp
      }) | Format-List
    }
    catch { $_ }
    finally {
      if ($shi) { [Marshal]::FreeHGlobal($shi) }
    }
  }
  end {
    if ($hndl) { [void]$s1::CloseHandle($hndl) }
    $collect | ForEach-Object { [void]$ta::Remove($_) }
  }
}

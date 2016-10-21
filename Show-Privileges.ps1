function Show-Privileges {
  <#
    .SYNOPSIS
        Retrieves user privileges from the process token.
  #>
  begin {
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
        [Runtime.InteropServices.CharSet]$CharSet = 'Auto',
        
        [Parameter()]
        [Runtime.InteropServices.CallingConvention]$CallingConvention = 'WinApi',
        
        [Parameter()]
        [String]$EntryPoint
      )
      
      begin {
        $mod = if (!($m = $ExecutionContext.SessionState.PSVariable.Get(
            'PowerShellDllImport'
        ))) {
          $mb = ([AppDomain]::CurrentDomain.DefineDynamicAssembly(
            (New-Object reflection.AssemblyName('PowerShellDllImport')), 'Run'
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
                $ErrorValue, [Runtime.InteropServices.CallingConvention]$CallingConvention,
                [Runtime.InteropServices.CharSet]$CharSet, $EntryPoint
              )
            )
            $fun.SetCustomAttribute($atr)
            
            $pin = $pin.CreateType()
          }
          $pin
        }
      }
    }
    
    function private:Invoke-Linq {
      param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String]$Method,
        
        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNull()]
        [Object[]]$Collection,
        
        [Parameter(Mandatory=$true, Position=2)]
        [Int32]$Condition
      )
      
      ([Linq.Enumerable].GetMember(
        $Method, [Reflection.MemberTypes]8,
        [Reflection.BindingFlags]24
      ) | Where-Object {
        $_.IsGenericMethod -and $_.GetParameters().Length -eq 2
      }).MakeGenericMethod([Type[]]@([Object])).Invoke($null, @(
        $Collection, $Condition
      ))
    }
    
    $s1 = New-DllImport kernel32 CloseHandle ([Boolean]) @([IntPtr])
    $s2 = New-DllImport kernel32 GetCurrentProcess ([IntPtr]) @()
    $s3 = New-DllImport advapi32 OpenProcessToken ([Boolean]) @(
        [IntPtr], [UInt32], [IntPtr].MakeByRefType()
    ) -SetLastError
    $s4 = New-DllImport advapi32 GetTokenInformation ([Boolean]) @(
        [IntPtr], [UInt32], [Byte[]], [UInt32], [UInt32].MakeByRefType()
    ) -SetLastError
    $s5 = New-DllImport advapi32 LookupPrivilegeName ([Boolean]) @(
        [String], [IntPtr], [Byte[]], [UInt32].MakeByRefType()
    ) -CharSet Unicode
    $s6 = New-DllImport advapi32 LookupPrivilegeDisplayName ([Boolean]) @(
        [String], [String], [Byte[]],
        [UInt32].MakeByRefType(), [UInt32].MakeByRefType()
    ) -CharSet Unicode
    
    $TOKEN_QUERY, $TokenPrivileges = 0x8, 0x3
    $len = [Runtime.InteropServices.Marshal]::SizeOf((
      $LUID_AND_ATTRIBUTES = [Activator]::CreateInstance(
        [Object].Assembly.GetType(
          'Microsoft.Win32.Win32Native+LUID_AND_ATTRIBUTES'
        )
      )
    ))
  }
  process {
    [IntPtr]$hndl = [IntPtr]::Zero
    [UInt32]$sz = 0
    
    try {
      if (!$s3::OpenProcessToken(
        $s2::GetCurrentProcess(), $TOKEN_QUERY, [ref]$hndl
      )) {
        throw New-Object InvalidOperationException(
          [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        )
      }
      
      if (!$s4::GetTokenInformation(
         $hndl, $TokenPrivileges, $null, $sz, [ref]$sz
      ) -and $sz -ne 0) {
        $buf = New-Object Byte[]($sz)
        if (!$s4::GetTokenInformation(
          $hndl, $TokenPrivileges, $buf, $sz, [ref]$sz
        )) {
          throw New-Object InvalidOperationException(
            [Runtime.InteropServices.Marshal]::GetLastWin32Error()
          )
        }
      }
      
      $PrivilegeCount = [BitConverter]::ToUInt32($buf[0..3], 0)
      # got LUID_AND_ATTRIBUTES[$PrivilegeCount], offset
      $buf, $j = $buf[4..$buf.Length], 0
      for ($i = 0; $i -lt $PrivilegeCount; $i++) {
        $gch = [Runtime.InteropServices.GCHandle]::Alloc(
          [Byte[]](Invoke-Linq Take (Invoke-Linq Skip $buf $j) $len), 'Pinned'
        )
        $laa = [Runtime.InteropServices.Marshal]::PtrToStructure(
          $gch.AddrOfPinnedObject(), [Type]$LUID_AND_ATTRIBUTES.GetType()
        )
        $gch.Free()
        
        $laa.GetType().GetFields([Reflection.BindingFlags]36) |
        ForEach-Object {
          Set-Variable $_.Name $_.GetValue($laa)
        }
        
        try {
          $lptr = [Runtime.InteropServices.Marshal]::AllocHGlobal(
            [Runtime.InteropServices.Marshal]::SizeOf(
              [Type]$LUID.GetType()
            )
          )
          [Runtime.InteropServices.Marshal]::StructureToPtr($LUID, $lptr, $true)
          
          $priv = New-Object Byte[](255)
          $sz = $priv.Length
          if ($s5::LookupPrivilegeName($null, $lptr, $priv, [ref]$sz)) {
            $priv = [Text.Encoding]::Unicode.GetString($priv).Split("`0")[0]
            $desc = New-Object Byte[](255)
            $sz, $lang = $desc.Length
            if ($s6::LookupPrivilegeDisplayName(
              $null, $priv, $desc, [ref]$sz, [ref]$lang
            )) {
              New-Object PSObject -Property @{
                Privilege = $priv
                Description = [Text.Encoding]::Unicode.GetString(
                    $desc
                ).Split("`0")[0]
                Attributes = if ($Attributes -band 1) {
                  'Default Enabled'
                } elseif ($Attributes -band 2) { 'Enabled' } else { 'Disabled' }
              } | Select-Object Privilege, Description, Attributes
            }
          }
        }
        catch { $_ }
        finally {
          if ($lptr) { [Runtime.InteropServices.Marshal]::FreeHGlobal($lptr) }
        }
        
        $j += $len
      }
    }
    catch { $_.Exception }
    finally {
      if ($hndl -ne [IntPtr]::Zero) { [void]$s1::CloseHandle($hndl) }
    }
  }
  end {}
}

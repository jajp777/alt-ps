function Get-SigningDate {
  <#
    .SYNOPSIS
        Retrives signing date of a file.
    .EXAMPLE
        PS C:\> Get-SigningData .\bin\whois.exe
  #>
  param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Path $_})]
    [String]$Path
  )
  
  begin {
    Add-Type -AssemblyName System.Security
    
    function private:Set-DllImport {
      param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String]$Module,
        
        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String]$Function,
        
        [Parameter(Mandatory=$true, Position=2)]
        [Type]$ReturnType,
        
        [Parameter(Mandatory=$true, Position=3)]
        [Type[]]$Parameters,
        
        [Parameter()]
        [Switch]$SetLastError,
        
        [Parameter()]
        [Runtime.InteropServices.CharSet]$CharSet = 'Auto',
        
        [Parameter()]
        [Runtime.InteropServices.CallingConvention]$CallingConvention = 'Winapi',
        
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
          
          Set-Variable PSCryptApi -Value $mb -Option Constant -Scope Global -Visibility Private
          $mb
        }
        else { $m.Value }
      }
      process {}
      end {
        try { $pin = $mod.GetType("$($Function)Sig") }
        catch {}
        finally {
          if (!$pin) {
            $pin = $mod.DefineType("$($Function)Sig", 'Public, BeforeFieldInit')
            $fun = $pin.DefineMethod(
              $Function, 'Public, Static, PinvokeImpl', $ReturnType, $Parameters
            )
            
            $Parameters | ForEach-Object { $i = 1 }{
              if ($_.IsByRef) { [void]$fun.DefineParameter($i, 'Out', $null) }
              $i++
            }
            
            ($dllimport = [Runtime.InteropServices.DllImportAttribute]).GetFields() |
            Where-Object {$_.Name -cmatch '\A(C|En|S)'} |ForEach-Object {
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
    
    $s1 = Set-DllImport crypt32 CryptQueryObject ([Boolean]) @(
      [Int32], [String], [Int32], [Int32], [Int32], [Int32].MakeByRefType(),
      [Int32].MakeByRefType(), [Int32].MakeByRefType(), [IntPtr].MakeByRefType(),
      [IntPtr].MakeByRefType(), [IntPtr].MakeByRefType()
    ) -SetLastError
    
    $s2 = Set-DllImport crypt32 CryptMsgGetParam ([Boolean]) @(
      [IntPtr], [Int32], [Int32], [Byte[]], [Int32].MakeByRefType()
    ) -SetLastError
    
    $s3 = Set-DllImport crypt32 CryptMsgClose ([Boolean]) @([IntPtr]) -SetLastError
    
    $s4 = Set-DllImport crypt32 CertCloseStore ([Boolean]) @(
      [IntPtr], [Int32]
    ) -SetLastError
    
    $Path = Convert-Path $Path
  }
  process {
    Get-AuthenticodeSignature $Path | ForEach-Object {
      $cert = $_
      if ($cert.SignerCertificate) {
        $pdwMsgAndCertEncodingType, $pdwContentType, $pdwFormatType = 0, 0, 0
        [IntPtr]$phCertStore = [IntPtr]::Zero
        [IntPtr]$phMsg = [IntPtr]::Zero
        [IntPtr]$ppvContext = [IntPtr]::Zero
        
        [void]$s1::CryptQueryObject(
          0x1, $cert.Path, 0x3FFE, 0xE, $null, [ref]$pdwMsgAndCertEncodingType,
          [ref]$pdwContentType, [ref]$pdwFormatType, [ref]$phCertStore,
          [ref]$phMsg, [ref]$ppvContext
        )
        
        $pcbData = 0
        [void]$s2::CryptMsgGetParam($phMsg, 0x1D, 0, $null, [ref]$pcbData)
        
        $pvData = New-Object Byte[]($pcbData)
        [void]$s2::CryptMsgGetParam($phMsg, 0x1D, 0, $pvData, [ref]$pcbData)
        
        $cms = New-Object Security.Cryptography.Pkcs.SignedCms
        $cms.Decode($pvData)
        
        foreach ($inf in $cms.SignerInfos) {
          foreach ($i in $inf.CounterSignerInfos) {
            ($i.SignedAttributes | Where-Object {
              $_.Oid.Value -eq '1.2.840.113549.1.9.5'
            }).Values | Select-Object -ExpandProperty SigningTime
          }
        }
        
        [void]$s3::CryptMsgClose($phMsg)
        [void]$s4::CertCloseStore($phCertStore, 0)
      }
    }
  }
  end {}
}

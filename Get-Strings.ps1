function Get-Strings {
  <#
    .SYNOPSIS
        Search strings in binary files.
    .EXAMPLE
        PS C:\> Get-Strings app.exe -b 100 -f 20
        !This program cannot be run in DOS mode.
    .EXAMPLE
        PS C:\> Get-Strings app.exe -n 7 -u -o
        31366:mscoree.dll
        31378:runtime error
        31398:TLOSS error
        ...
  #>
  param(
    [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
    [ValidateScript({Test-Path $_})]
    [String]$FileName,
    
    [Alias('b')]
    [UInt32]$BytesToProcess = 0,
    
    [Alias('f')]
    [UInt32]$BytesOffset = 0,
    
    [Alias('n')]
    [Byte]$StringLength = 3,
    
    [Alias('o')]
    [Switch]$StringOffset,
    
    [Alias('u')]
    [Switch]$Unicode
  )
  
  begin {
    $FileName = Resolve-Path $FileName
    
    $enc = switch ($Unicode) {
      $true  {[Text.Encoding]::Unicode}
      $false {[Text.Encoding]::UTF7}
    }
    
    function private:Read-Buffer([Byte[]]$Bytes) {
      ([Regex]"[\x20-\x7E]{$StringLength,}").Matches(
        $enc.GetString($Bytes)
      ) | ForEach-Object {
        if ($StringOffset) {'{0}:{1}' -f $_.Index, $_.Value} else {$_.Value}
      }
    }
  }
  process {
    try {
      $fs = [IO.File]::OpenRead($FileName)
      #impossible to read more than file length is
      if ($BytesToProcess -ge $fs.Length -or $BytesOffset -ge $fs.Length) {
        throw New-Object InvalidOperationException('Out of stream.')
      }
      #if offset defined
      if ($BytesOffset -gt 0) {[void]$fs.Seek($BytesOffset, [IO.SeekOrigin]::Begin)}
      #bytes to process
      $buf = switch ($BytesToProcess -gt 0) {
        $true  {New-Object Byte[] ($fs.Length - ($fs.Length - $BytesToProcess))}
        $false {New-Object Byte[] $fs.Length}
      }
      [void]$fs.Read($buf, 0, $buf.Length)
      Read-Buffer $buf
    }
    catch { $_.Exception }
    finally {
      if ($fs) {
        $fs.Dispose()
        $fs.Close()
      }
    }
  }
  end {
  }
}

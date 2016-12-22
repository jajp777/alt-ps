function Get-Strings {
  <#
    .SYNOPSIS
        Search strings in binary files.
    .EXAMPLE
        PS C:\> Get-Strings .\bin\app.exe -b 100 -f 20 -o
        57:!This program cannot be run in DOS mode.
    .EXAMPLE
        PS C:\> Get-Item .\bin\app.exe | Get-Strings -u
        ...
    .NOTES
        Author: greg zakharov
  #>
  [CmdletBinding(DefaultParameterSetName='Path')]
  param(
    [Parameter(Mandatory=$true,
               ParameterSetName='Path',
               Position=0,
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [String]$Path,
    
    [Parameter(Mandatory=$true,
               ParameterSetName='LiteralPath',
               Position=0,
               ValueFromPipeline=$false,
               ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [Alias('PSPath')]
    [String]$LiteralPath,
    
    [Parameter()][Alias('b')][UInt32]$BytesToProcess = 0,
    [Parameter()][Alias('f')][UInt32]$BytesOffset    = 0,
    [Parameter()][Alias('n')][Byte]  $StringLength   = 3,
    [Parameter()][Alias('o')][Switch]$StringOffset,
    [Parameter()][Alias('u')][Switch]$Unicode
  )
  
  begin {
    if ($PSCmdlet.ParameterSetName -eq 'Path') {
      $PipelineInput = !$PSBoundParameters.ContainsKey('Path')
    }
    
    function private:Find-Strings {
      param(
        [Parameter(Mandatory=$true)]
        [IO.FileInfo]$File
      )
      
      $enc = switch ($Unicode) {
        $true  { [Text.Encoding]::Unicode }
        $false { [Text.Encoding]::UTF7 }
      }
      
      try {
        $fs = [IO.File]::OpenRead($File.FullName)
        # impossible to read more than file length is
        if ($BytesToProcess -ge $fs.Length -or $BytesOffset -ge $fs.Length) {
          throw New-Object InvalidOperationException('Out of stream.')
        }
        # offset has been defined
        if ($BytesOffset -gt 0) { [void]$fs.Seek($BytesOffset, [IO.SeekOrigin]::Begin) }
        # bytes to process
        $buf = switch ($BytesToProcess -gt 0) {
          $true  { New-Object Byte[]($fs.Length - ($fs.Length - $BytesToProcess)) }
          $false { New-Object Byte[]($fs.Length) }
        }
        [void]$fs.Read($buf, 0, $buf.Length)
        # convert bytes to strings
        ([Regex]"[\x20-\x7E]{$StringLength,}").Matches($enc.GetString($buf)) |
        ForEach-Object {
          if ($StringOffset) { '{0}:{1}' -f $_.Index, $_.Value } else { $_.Value }
        }
      }
      catch { Write-Verbose $_ }
      finally {
        if ($fs) { $fs.Dispose() }
      }
    }
  }
  process {}
  end {
    if ($PSCmdlet.ParameterSetName -eq 'Path') {
      switch ($PipelineInput) {
        $true  { Find-Strings $Path }
        $false { Find-Strings (Get-Item $Path) }
      }
    }
    else { Find-Strings (Get-Item -LiteralPath $LiteralPath) }
  }
}

# Export-ModuleMember -Function Get-Strings

function Get-VTReport {
  <#
    .SYNOPSIS
        Retrieves VirusTotal scan report of a [file|url|ip|domain|hash].
    .EXAMPLE
        PS C:\> Get-VTReport -Path C:\sandbox\app.exe
    .EXAMPLE
        PS C:\> Get-VTReport -Url github.com
    .EXAMPLE
        PS C:\> Get-VTReport -IP 192.30.253.113
    .EXAMPLE
        PS C:\> Get-VTReport -Domain github.com
    .EXAMPLE
        PS C:\> Get-VTReport -Hash 046041dd9778c176eb7b4c32449e59c4
    .NOTES
        Author: greg zakharov
        Remark: hash type (md5, sha1 or sha256) doesn't matter.

        Disclaimer
        -----------
        All public keys used with this script HAS NOT BEEN STOLED, they
        was found in binary files distributed by their owners. You can
        check this by yourself, for example:

        PS C:\> Get-Strings .\sysinternals\sigcheck.exe -n 64

        Get-Strings script can be found in 'tools' directory of current
        repository.
  #>
  [CmdletBinding(DefaultParameterSetName='Path')]
  param(
    [Parameter(ParameterSetName='Path', Mandatory=$true, Position=0)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Path $_})]
    [String]$Path,

    [Parameter(ParameterSetName='Url', Mandatory=$true, Position=0)]
    [ValidateNotNullOrEmpty()]
    [String]$Url,

    [Parameter(ParameterSetName='IP', Mandatory=$true, Position=0)]
    [ValidateNotNullOrEmpty()]
    [IPAddress]$IP,

    [Parameter(ParameterSetName='Domain', Mandatory=$true, Position=0)]
    [ValidateNotNullOrEmpty()]
    [String]$Domain,

    [Parameter(ParameterSetName='Hash', Mandatory=$true, Position=0)]
    [ValidateNotNullOrEmpty()]
    [String]$Hash
  )

  begin {
    function private:Get-SHA256Sum([String]$Path) {
      if (([IO.FileInfo]$Path).Length -eq 0) {
        throw New-Object InvalidOPerationException('File has null length.')
      }

      try {
        $fs = [IO.File]::OpenRead($Path)
        -join ([Security.Cryptography.HashAlgorithm]::Create(
          'SHA256'
        ).ComputeHash($fs) | ForEach-Object {'{0:x2}' -f $_})
      }
      finally {
        if ($fs) { $fs.Dispose() }
      }
    }

    function private:Convert-Json([String]$Json) {
      Add-Type -AssemblyName System.Web.Extensions
      (
        New-Object Web.Script.Serialization.JavaScriptSerializer
      ).DeserializeObject($Json)
    }

    $json = @'
      {
        "url" : "https://www.virustotal.com/vtapi/v2/%s/report?apikey=%k&",
        "keys" : {
          "microsoft_sysinternals":"4e3202fdbe953d628f650229af5b3eb49cd46b2d3bfe5546ae3c5fa48b554e0c",
          "PepiMK":"c08e61058c2d1178eac28ad5c9903a99802e0bc64facd386a44bcaa8c707dba8",
          "virustotal_uploader":"f25133d9068704c23335fc39a7351828fa80c5dde894d731d5450cf8ab8569e8",
          "khanta":"bd527801758bee752fe0aef5a52e87f5020eb1359f0b3b0e458b596373db1ce0",
          "DarkCoderSc":"4d1ee14a3191ba1afde5261326dcd7e81793afacb6aa7e46d0b467bc6ebcd367"
        }
      }
'@
    $r, $k = (New-Object Random), ($raw = Convert-Json $json).keys
    $uri = $raw.url -replace '%k', "$($k[($k.Keys -as [Array])[$r.Next($k.Count)]])"
  }
  process {
    $uri = switch ($PSCmdlet.ParameterSetName) {
      'Path'   {
        "$($uri -replace '%s', 'file')resource=$(Get-SHA256Sum (Resolve-Path $Path))"
        $method = 'POST'
      }
      'Url'    { "$($uri -replace '%s', 'url')resource=${Url}";$method = 'POST' }
      'IP'     { "$($uri -replace '%s', 'ip-address')ip=${IP}";$method = 'GET' }
      'Domain' { "$($uri -replace '%s', 'domain')domain=${Domain}";$method = 'GET' }
      'Hash'   { "$($uri -replace '%s', 'file')resource=${Hash}";$method = 'POST' }
    }
  }
  end {
    $wr = [Net.WebRequest]::Create($uri)
    $wr.Method = $method
    $wr.ContentType = 'application/json; charset=utf-8'
    $wr.ContentLength = 0

    $response = $wr.GetResponse()
    try {
      $rs = $response.GetResponseStream()
      $sr = New-Object IO.StreamReader($rs)

      $res = $sr.ReadToEnd()
    }
    finally {
      if ($sr) { $sr.Dispose() }
      if ($rs) { $rs.Dispose() }
    }

    if ([String]::IsNullOrEmpty($res)) {
      throw New-Object IO.IOException('Could not finish request.')
    }

    Convert-Json $res
  }
}

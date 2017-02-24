<#
  .SYNOPSIS
      This code demonstrates a technique of combination
      PowerShell with Ruby.
  .NOTES
      Author: greg zakharov
      Requirements: Ruby 2.X stored into $env:path
#>
ruby -x $MyInvocation.MyCommand.Path $args
<#
#!ruby
require 'win32api'

FORMAT_MESSAGE_FROM_SYSTEM = 0x00001000
LANG_NEUTRAL               = 0x00000000
SUBLANG_DEFAULT            = 0x00000001

def getlasterror(err)
  def MAKELANGID(p, s)
    return ((s << 10) | p)
  end

  msg = ('\x00' * 256).force_encoding('utf-16le')
  if 0 == (len = (
    Win32API.new 'kernel32', 'FormatMessageW', 'IPIIPIP', 'I'
  ).call(
    FORMAT_MESSAGE_FROM_SYSTEM, nil, err,
    MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
    msg, msg.size, nil
  )) then
    puts 'Unknown error has been occured.'
  end

  puts msg[0, len].encode('utf-8')
end

getlasterror(ARGV[0].to_i)
#>

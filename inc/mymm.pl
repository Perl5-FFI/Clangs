package mymm;

use strict;
use warnings;
use 5.024;
use experimental qw( signatures );
use FFI::CheckLib qw( find_lib );

{
  my @path;

  # Try libclang provided by homebrew if available
  push @path, File::Glob::bsd_glob('/usr/local/Cellar/llvm/*/lib')
    if $^O eq 'darwin';

  my @libs = FFI::CheckLib::find_lib
    lib => '*',
    libpath => \@path,
    verify => sub ($name, @) {
      return 1 if $name =~ /^clang-([0-9\.]+)$/;
      return 1 if $name eq 'clang';
      return 0;
    }
  ;

  unless(@libs)
  {
    say "Unable to find libclang";
    exit;
  }
}

1;
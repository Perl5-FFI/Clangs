use Test2::V0 -no_srand => 1;
use 5.024;
use Test2::Util::Table qw( table );
use FFI::Clang;

subtest 'libs' => sub {

  my @libs = FFI::Clang->libs->@*;

  is
    \@libs,
    bag {
      item object {
        call valid => T()
      };
      etc;
    },
    '->libs has at least one item that is valid'
  ;

  if(@libs)
  {
    diag '';
    diag $_ for table
      header => [ 'dir', 'name', 'version', 'human' ],
      rows => [
        map { [
          $_->path->parent->stringify,
          $_->path->basename,
          $_->version,
          $_->version_string,
        ]} @libs,
      ]
    ;
  }

};

done_testing;
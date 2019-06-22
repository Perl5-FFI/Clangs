use Test2::V0 -no_srand => 1;
use 5.024;
use Test2::Util::Table qw( table );
use Clangs;

subtest 'libs' => sub {

  my @libs = Clangs->libs->@*;

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

  is(
    Clangs->default_lib,
    object {
      call valid => T();
    },
    '->default_libs returns valid lib'
  );

};

done_testing;
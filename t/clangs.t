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

subtest 'generate_class' => sub {

  my $i = 0;

  foreach my $lib (Clangs->libs->@*)
  {
    next unless $lib->valid;
    subtest $lib->version_string => sub {

      my $class = "Foo::Bar@{[ $i++ ]}";
      $lib->generate_classes($class);

      my $index = "${class}::Index"->new;
      isa_ok $index, "${class}::Index";

      is $index->ptr, D(), "index->ptr = @{[ $index->ptr ]}";

      undef $index;
      pass 'DEMOLISH does not crash';

    };
  }

};

done_testing;
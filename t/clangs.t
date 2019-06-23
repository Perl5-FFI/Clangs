use Test2::V0 -no_srand => 1;
use 5.024;
use Test2::Util::Table qw( table );
use Test::Memory::Cycle;
use Test::Moose::More;
use Scalar::Util qw( weaken );
use Clangs;

subtest 'sugar removal' => sub {
  check_sugar_removed_ok 'Clangs';
  check_sugar_removed_ok 'Clangs::Lib';
  check_sugar_removed_ok 'Clangs::Index';
};

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

      my $ref = $index;
      weaken $ref;
      is $ref, D(), 'weak ref ok';

      memory_cycle_ok $index, 'no memory leak';

      #my $demolished;
      #my $mock = mock "Clangs::Index" => (
      #  after => [
      #    DEMOLISH => sub {
      #      $demolished++;
      #    }
      #  ],
      #);

      undef $index;
      is $ref, U(), 'Index freed';

      #is $demolished, T(), 'DEMOLISH called';

    };
  }

};

done_testing;
use Test2::V0 -no_srand => 1;
use 5.024;
use Test2::Util::Table qw( table );
use Test::Memory::Cycle;
use Test::Moose::More;
use Scalar::Util qw( weaken );
use File::Which qw( which );
use Capture::Tiny qw( capture_merged );
use Clangs;

subtest 'sugar removal' => sub {
  check_sugar_removed_ok 'Clangs';
  check_sugar_removed_ok 'Clangs::Lib';
  check_sugar_removed_ok 'Clangs::Index';
  check_sugar_removed_ok 'Clangs::TranslationUnit';
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
      does_ok $index, 'Clangs::Index';

      is $index->ptr, D(), "index->ptr = @{[ $index->ptr ]}";

      subtest 'tu without full argv' => sub {
        my $tu = "${class}::TranslationUnit"->new(
          index => $index,
          filename => 'corpus/foo.c',
          full_argv => 0,
        );
        does_ok $tu, 'Clangs::TranslationUnit';
        is $tu->spelling, 'corpus/foo.c', 'tu->spelling';
      };

      subtest 'to with full argv' => sub {
        my $tu = "${class}::TranslationUnit"->new(
          index     => $index,
          filename  => 'corpus/foo.c',
          full_argv => 1,
        );
        does_ok $tu, 'Clangs::TranslationUnit';
        is $tu->spelling, 'corpus/foo.c', 'tu->spelling';
      };

      subtest 'tu with ast' => sub {
        my $clang = which 'clang';
        skip_all 'requires clang exe' unless $clang;

        # most likely the problem here is that we need for clang exe
        # to match libclang.
        my $todo = todo 'not quite right';
        my @cmd = qw( clang -emit-ast corpus/foo.c -o corpus/foo.ast );
        my($out, $exit) = capture_merged {
          print "+ @cmd";
          system @cmd;
          $?;
        };
        note $out;
        is $exit, 0, 'exit ok';
        ok -f "corpus/foo.ast", "apparently generated ast";

        local $@ = '';
        eval {
          my $tu = "${class}::TranslationUnit"->new(
            index     => $index,
            filename  => 'corpus/foo.ast',
          );
          does_ok $tu, 'Clangs::TranslationUnit';
          like $tu->spelling, qr{corpus/foo.c$};
        };
        is "$@", '', 'no exception';

        unlink 'corpus/foo.ast';
      };

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

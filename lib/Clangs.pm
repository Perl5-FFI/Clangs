package Clangs {

  use MooseX::Singleton;
  use 5.024;
  use experimental 'refaliasing';
  use experimental 'signatures';

  use FFI::Platypus 0.88;
  use FFI::CheckLib ();
  use Path::Tiny ();
  use File::Glob ();
  use Sort::Versions ();
  use Moose::Util ();

# ABSTRACT: Interface to libclang useful for FFI development
# VERSION

  has libs => (
    is      => 'ro',
    isa     => 'ArrayRef[Clangs::Lib]',
    lazy    => 1,
    default => sub ($self) {

      my @list;

      my @path;

      # Try libclang provided by homebrew if available
      push @path, File::Glob::bsd_glob('/usr/local/Cellar/llvm/*/lib')
        if $^O eq 'darwin';

      FFI::CheckLib::find_lib
        lib => '*',
        libpath => \@path,
        verify => sub ($name, $path, @) {
          if($name =~ /^clang-(?<version>[0-9\.]+)$/)
          {
            push @list, Clangs::Lib->new(
              path    => Path::Tiny->new($path)->absolute,
              version => $+{version},
            );
          }
          elsif($name eq 'clang')
          {
            push @list, Clangs::Lib->new(
              path    => Path::Tiny->new($path)->absolute,
            );
          }
        }
      ;

      [sort { Sort::Versions::versioncmp($b->version, $a->version) } @list];
    },
  );

  has default_lib => (
    is      => 'ro',
    isa     => 'Maybe[Clangs::Lib]',
    lazy    => 1,
    default => sub ($self) {
      [grep { $_->valid } $self->libs->@*]->[0];
    },
  );

  package Clangs::Lib {

    use Moose;
    use 5.024;
    use experimental 'refaliasing';
    use experimental 'signatures';

    has path => (
      is       => 'ro',
      isa      => 'Path::Tiny',
      required => 1,
    );

    has version => (
      is      => 'ro',
      isa     => 'Str',
      lazy    => 1,
      default => sub ($self) {
        $self->version_string =~ /version (?<version>[0-9\.]+)/ ? $+{version} : 'unknown';
      },
    );

    has version_string => (
      is      => 'ro',
      isa     => 'Maybe[Str]',
      lazy    => 1,
      default => sub ($self) {
        my $ffi = FFI::Platypus->new;
        $ffi->lib($self->path->stringify);

        local $@ = '';
        my($get_version, $get_c_string, $dispose_string) = eval {
          (
            $ffi->function( clang_getClangVersion => []         => 'opaque' ),
            $ffi->function( clang_getCString      => ['opaque'] => 'string' ),
            $ffi->function( clang_disposeString   => ['opaque'] => 'void'   ),
          )
        };

        if(!$@)
        {
          my $cx_version = $get_version->();
          my $c_version = $get_c_string->($cx_version);
          $dispose_string->($cx_version);
          return $c_version;
        }
        else
        {
          return;
        }

      },
    );

    has valid => (
      is      => 'ro',
      isa     => 'Bool',
      lazy    => 1,
      default => sub ($self) {
        defined $self->version_string ? 1 : 0;
      },
    );

    sub generate_classes ($self, $class)
    {
      my $ffi = FFI::Platypus->new;
      $ffi->lib($self->path->stringify);
      $ffi->mangler(sub ($symbol) {
        $symbol =~ s/^/clang_/r;
      });

      my $build = sub ($xsub, $, @args) {
        $xsub->(@args);
      };

      my $method = sub ($xsub, $self) {
        $xsub->($self->ptr);
      };

      eval qq{ package ${class}::Index; use Moose; };
      die if $@;

      my $f1 = $ffi->function( createIndex => ['int','int'] => 'opaque', $build );
      join('::', $class, 'Index')->meta->add_method(_create_index => sub { $f1->call(@_) });
      my $f2 = $ffi->function( disposeIndex => ['opaque'] => 'void', $method );
      join('::', $class, 'Index')->meta->add_method(_dispose_index => sub { $f2->call(@_) });

      Moose::Util::apply_all_roles(join('::', $class, 'Index'), 'Clangs::Index');
    }

  }

  package Clangs::Index {

    use Moose::Role;
    use 5.024;
    use experimental 'refaliasing';
    use experimental 'signatures';

    requires '_create_index';
    requires '_dispose_index';

    has exclude_declarations_from_pch => (
      is      => 'ro',
      isa     => 'Bool',
      default => sub { 1 },
    );

    has display_diagnostics => (
      is      => 'ro',
      isa     => 'Bool',
      default => sub { 1 },
    );

    has ptr => (
      is        => 'ro',
      isa       => 'Int',
      lazy      => 1,
      predicate => 'has_ptr',
      default   => sub ($self) {
        $self->_create_index($self->exclude_declarations_from_pch, $self->display_diagnostics);
      }
    );

    sub DEMOLISH ($self, $global)
    {
      if($self->has_ptr && !$global)
      {
        $self->_dispose_index;
      }
    }

  }

}

1;
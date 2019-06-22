package FFI::Clang {

  use MooseX::Singleton;
  use 5.024;
  use experimental 'refaliasing';
  use experimental 'signatures';

  use FFI::Platypus 0.88;
  use FFI::CheckLib ();
  use Path::Tiny ();
  use File::Glob ();
  use Sort::Versions ();

# ABSTRACT: Interface to libclang useful for FFI development
# VERSION

  has libs => (
    is      => 'ro',
    isa     => 'ArrayRef[FFI::Clang::Lib]',
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
            push @list, FFI::Clang::Lib->new(
              path    => Path::Tiny->new($path)->absolute,
              version => $+{version},
            );
          }
          elsif($name eq 'clang')
          {
            push @list, FFI::Clang::Lib->new(
              path    => Path::Tiny->new($path)->absolute,
            );
          }
        }
      ;

      [sort { Sort::Versions::versioncmp($b->version, $a->version) } @list];
    },
  );

  package FFI::Clang::Lib {

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

  }

}

1;
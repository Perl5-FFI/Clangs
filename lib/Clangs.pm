package Clangs {

  use MooseX::Singleton;
  use 5.026;
  use experimental 'refaliasing';
  use experimental 'signatures';
  use namespace::autoclean;

  use FFI::Platypus 0.91;
  use FFI::CheckLib ();
  use Path::Tiny ();
  use File::Glob ();
  use Sort::Versions ();
  use Moose::Util ();
  use Moose::Meta::Class ();

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

  __PACKAGE__->meta->make_immutable;

  package Clangs::Lib {

    use Moose;
    use 5.026;
    use experimental 'refaliasing';
    use experimental 'signatures';
    use namespace::autoclean;

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
        my $ffi = FFI::Platypus->new( api => 1, experimental => 1 );
        $ffi->lib($self->path->stringify);
        $ffi->mangler(sub ($symbol) { $symbol =~ s/^/clang_/r });

        local $@ = '';
        my($get_version, $get_c_string, $dispose_string) = eval {
          (
            $ffi->function( getClangVersion => []         => 'opaque' ),
            $ffi->function( getCString      => ['opaque'] => 'string' ),
            $ffi->function( disposeString   => ['opaque'] => 'void'   ),
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
      my $ffi = FFI::Platypus->new( api => 1, experimental => 1 );
      $ffi->lib($self->path->stringify);
      $ffi->mangler(sub ($symbol) { $symbol =~ s/^/clang_/r });
      $ffi->type('opaque' => 'CXIndex');
      $ffi->type('opaque' => 'CXTranslationUnit');
      $ffi->type('opaque' => 'CXUnsavedFile');
      if(eval { $ffi->type('enum'); 1 })
      {
        $ffi->type('enum' => 'CXErrorCode');
      }
      else
      {
        $ffi->type('uint32' => 'CXErrorCode');
      }

      {
        my $get_c_string   = $ffi->function( getCString      => ['opaque'] => 'string' )->sub_ref;
        my $dispose_string = $ffi->function( disposeString   => ['opaque'] => 'void'   )->sub_ref;

        $ffi->custom_type( 'CXString' => {
          native_type => 'opaque',
          native_to_perl => sub ($ptr, $) {
            my $str = $get_c_string->($ptr);
            $dispose_string->($ptr);
            $str;
          },
        });
      }

      my $make_make = sub ($wrapper) {
        sub ($name, $args, $ret) {
          $ffi->function( $name => $args => $ret, $wrapper )->sub_ref;
        }
      };

      my $make_build  = $make_make->(sub ($xsub, $, @args) {
        @_ = @args;
        goto &$xsub;
      });

      my $make_method = $make_make->(sub ($xsub, $self, @args) {
        @_ = ($self->ptr, @args);
        goto &$xsub;
      });

      {
        my $meta = Moose::Meta::Class->create(
          "${class}::Index",
          methods => {
            _create_index  => $make_build ->( createIndex  => ['int','int'] => 'CXIndex' ),
            _dispose_index => $make_method->( disposeIndex => ['CXIndex']    => 'void'   ),
            lib            => sub { $self },
          },
          superclasses => ['Moose::Object'],
          roles        => ['Clangs::Index'],
        );
        $meta->make_immutable;
      }

      {
        my $meta = Moose::Meta::Class->create(
          "${class}::TranslationUnit",
          methods => {
            _create_translation_unit_2 => $make_build->( createTranslationUnit2 => [
              'CXIndex',             # Index
              'string',              # ast_filename
              'CXTranslationUnit*',  # (CXTranslationUnit*) out_TU
            ] => 'CXErrorCode' ),
            _parse_translation_unit_2 => $make_build->( parseTranslationUnit2 => [
              'CXIndex',             # Index
              'string',              # filename
              'string[]',            # command line args
              'int',                 # num_command_line_args
              'CXUnsavedFile[]',     # (CXUnsavedFile*) unsaved_files
              'uint',                # num_unsaved_files
              'uint',                # options
              'CXTranslationUnit*',  # (CXTranslationUnit*) out_TU
            ] => 'CXErrorCode'),
            _parse_translation_unit_2_full_argv => $make_build->( parseTranslationUnit2FullArgv => [
              'CXIndex',             # Index
              'string',              # filename
              'string[]',            # command line args
              'int',                 # num_command_line_args
              'CXUnsavedFile[]',     # (CXUnsavedFile*) unsaved_files
              'uint',                # num_unsaved_files
              'uint',                # options
              'CXTranslationUnit*',  # (CXTranslationUnit*) out_TU
            ] => 'CXErrorCode'),
            _dispose_translation_unit => $make_method->( disposeTranslationUnit => ['CXTranslationUnit'] => 'void' ),
            spelling => $make_method->( getTranslationUnitSpelling => ['CXTranslationUnit'] => 'CXString' ),
          },
          superclass => ['Moose::Object'],
          roles      => ['Clangs::TranslationUnit'],
        );
        $meta->make_immutable;
      }
    }

    __PACKAGE__->meta->make_immutable;
  }

  package Clangs::Index {

    use Moose::Role;
    use 5.026;
    use experimental 'refaliasing';
    use experimental 'signatures';
    use namespace::autoclean;

    requires '_create_index';
    requires '_dispose_index';
    requires 'lib';

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

  package Clangs::TranslationUnit {

    use Moose::Role;
    use 5.026;
    use experimental 'refaliasing', 'signatures', 'declared_refs';
    use namespace::autoclean;
    use MooseX::Types::Path::Tiny qw( Path );

    requires '_create_translation_unit_2';
    requires '_parse_translation_unit_2';
    requires '_parse_translation_unit_2_full_argv';
    requires '_dispose_translation_unit';
    requires 'spelling';

    has full_argv => (
      is      => 'ro',
      isa     => 'Bool',
      default => sub { 0 },
    );

    has command_line => (
      is      => 'ro',
      isa     => 'ArrayRef[Str]',
      lazy    => 1,
      default => sub ($self) {
        $self->full_argv ? [$0] : [];
      },
    );

    has ptr => (
      is        => 'ro',
      isa       => 'Int',
      lazy      => 1,
      predicate => 'has_ptr',
      default   => sub ($self) {

        my $code;

        if($self->filename->basename =~ /\.ast$/)
        {
          my $ptr;
          $code = $self->_create_translation_unit_2(
            $self->index->ptr,
            $self->filename->stringify,
            \$ptr,
          );
          return $ptr unless $code != 0;
        }
        elsif($self->filename->basename =~ /\.[ch]$/)
        {
          my $ptr;
          my \@command_line = $self->command_line;
          my @args = (
            $self->index->ptr,
            $self->filename->stringify,
            \@command_line,
            scalar(@command_line),
            [],
            0,
            0,
            \$ptr,
          );
          $code = !$self->full_argv
            ? $self->_parse_translation_unit_2(@args)
            : $self->_parse_translation_unit_2_full_argv(@args);
          return $ptr unless $code != 0;
        }
        else
        {
          Carp::croak "unknown filetype: @{[ $self->filename ]}";
        }

        # handle it when $code is not 0
        warn "code = $code";
        ...;
      },
    );

    has index => (
      is       => 'ro',
      isa      => 'Clangs::Index',
      required => 1,
    );

    has filename => (
      is       => 'ro',
      isa      => Path,
      required => 1,
      coerce   => 1,
    );

    sub DEMOLISH ($self, $global)
    {
      if($self->has_ptr && !$global)
      {
        $self->_dispose_translation_unit;
      }
    }

  }

}

1;

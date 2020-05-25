#!/usr/bin/perl
############################################################################
##
## Evolver -- perl-based static web site generator
## (c) Vladi Belperchinov-Shabanski "Cade" 2002-2020
## http://cade.datamax.bg/  <cade@bis.bg>  <cade@datamax.bg>
##
############################################################################
use strict;
use Tie::IxHash;
use File::Glob;
use Data::Dumper;
use Exception::Sink;
use Data::Tools;
use Cwd qw( abs_path getcwd );
use File::Copy;
use Storable;
use Imager;
use Image::EXIF;
use Hash::Merge qw( merge );
use Text::Markdown;

our $VERSION = '20200525';

our $DEBUG = $ENV{ 'DEBUG' };

my %TEMPLATE_TYPES =  (
                        'HTML' => \&process_html,
                        'MD'   => \&process_markdown,
                      );

### OPTS ###################################################################

$Data::Dumper::Sortkeys = 1;

our $HELP = "usage: $0 config-file\n";

our $opt_config;
our $opt_force    = 0;
our $opt_stats_up = 0;

my $break_main_loop = 0;
my $startup_path = getcwd();

our @args;

while( $_ = shift @ARGV )
  {
  if(/^-f$/) { $opt_force++; next; }
  if(/^-d$/) { $DEBUG++;     next; }
  if(/^-u$/) { $opt_stats_up++; next; }
  if( /^(--?h(elp)?|help)$/io )
    {
    print $HELP;
    exit;
    }
  push @args, $_;
  }

$opt_config = shift @args;
die "missing config file name as 1st arg\n" unless $opt_config;
$opt_config = abs_path( $opt_config );
die "cannot read config-file [$opt_config]\n" unless -r $opt_config;

############################################################################

$SIG{ 'INT'  } = sub { $break_main_loop = 1; };
$SIG{ 'HUP'  } = sub { $break_main_loop = 1; };
$SIG{ 'TERM' } = sub { $break_main_loop = 1; };

print "config file: $opt_config\n";

my $CONFIG = hash_load( $opt_config );
print Dumper( $CONFIG );

our $IN   = $CONFIG->{ 'IN'  };
our $OUT  = $CONFIG->{ 'OUT' };
our $ROOT = file_path( $opt_config );

die "config file has to have IN and OUT directives\n" unless $IN and $OUT;

$IN  = abs_path( $IN  );
$OUT = abs_path( $OUT );

$CONFIG->{ 'IN'   } = $IN;
$CONFIG->{ 'OUT'  } = $OUT;

print " IN: $IN\n";
print "OUT: $OUT\n";

process_dir( '.', -1 );

### PROCESS DIRS AND FILES ###################################################

sub process_dir
{
  my $path  = shift;
  my $level = shift() + 1;
  
  my $pad = "\t" x $level;

  print "$pad --------------------------------------[$path]-------\n";

  dir_path_ensure( "$OUT/$path", MASK => oct( '755' ) );
  
  my @d;
  my @e = read_dir_entries( "$IN/$path" );
  
  @e = grep { ! /^\./ } @e; # skip dot files/dirs
  @e = grep { ! /\.in\.[a-z]+$/ } @e; # skip include files

  my $lopt = load_lopt( $path );
#  print Dumper( $path, \@d, \@e, $lopt );

  my $index_ok;
  for my $e ( @e )
    {
    my $ee = "$path/$e";
    if( -d "$IN/$ee" )
      {
      process_dir( $ee, $level );
      }
    else
      {
      $e =~ /^(.+?)\.([a-z]+)$/i or die "cannot recognise extension type for file [$ee]\n";
      my $eef = $1;
      my $eet = $2;
      
      $index_ok = 1 if $eef eq 'index';
      
      if( exists $TEMPLATE_TYPES{ uc $eet } )
        {
        process_file( $path, $eef, $eet );
        }
      else
        {
        my $fr =  "$IN/$path/$e";
        my $to = "$OUT/$path/$e";
        copy( $fr, $to ) or die "cannot copy file [$fr] to [$to] error [$!]\n";
        print "$pad copy: $e\n";
        }  
      }
    }

  if( ! $index_ok )
    {
    print "$pad index not found, creating default one...\n";

    my $to = "$OUT/$path/index.html";
  
    file_save( $to, load_in_file( $path, 'index' ) );
    }
}

sub process_file
{
  my $path = shift;
  my $name = shift;
  my $type = shift;
  
  my $pc = $TEMPLATE_TYPES{ uc $type } or die "unknown template type ($type) for [$path/$name.$type]";

  my $fr =  "$IN/$path/$name.$type";
  my $to = "$OUT/$path/$name.html";
  
  file_save( $to, $pc->( file_load( $fr ) ) );
  
  return 1;
}

sub process_html
{
  my $tin = shift; # text in
  
  my $tout = preprocess_html( $tin );

  return $tout;
}

sub process_markdown
{
  my $tin = shift; # text in

  my $tout = preprocess_markdown( $tin );
  
  return $tout;
}

### LOPT FINDER/LOADER #####################################################

our %LOPT_DEFAULTS = (
                     DIR_COLS   => 3,
                     GAL_COLS   => 5,
                     THUMB_SIZE => 128,
                     WEB_SIZE_W => 800,
                     WEB_SIZE_H => 600,
                     COPY_SIZE  => 1280,
                     );

our %LOPT_CACHE;
sub load_lopt
{
  my $path = shift;

  my $hrc = $LOPT_CACHE{ "$path/" };
  return wantarray ? %$hrc : $hrc if $hrc;

  my %lopt = %LOPT_DEFAULTS;
  
  my $base_path = file_path( $path );

  my $hrp; # parent
  if( $base_path )
    {
    $hrp = $LOPT_CACHE{ $base_path };
    die "empty cache for [$base_path]\n" unless $hrp;
    }
  else
    {
    $hrp = {};
    }

  # merge default and parent dir options
  %lopt = ( %lopt, %$hrp );
  
  # remove volatile keys for parent options
  for( map { substr( $_, 1 ) } grep { /^!/ } keys %lopt )
    {
    delete $lopt{ "!$_" }; # volatile
    delete $lopt{ $_ };    # remapped
    };

  # load local path options
  my $hr = hash_load( "$IN/$path/.opt" ) || {};
  hash_uc_ipl( $hr );

  # merge parent options and current path options
  %lopt = ( %lopt, %$hr );
  
  # remap volatile keys, keep originals
  for( map { substr( $_, 1 ) } grep { /^!/ } keys %lopt )
    {
    $lopt{ $_ } = $lopt{ "!$_" };
    }
  $lopt{ 'PATH' } = $path;

  $LOPT_CACHE{ "$path/" } = \%lopt;

  return wantarray ? %lopt : \%lopt;
}

### CODE LOADER ############################################################

my %CODE_CACHE;

sub exec_mod
{
  my $name  = lc shift;
  
  return $CODE_CACHE{ $name }->( @_ ) if exists $CODE_CACHE{ $name };

  my $file = $ROOT . "mod/$name.pm";
  
  die "cannot load module [$name] from file [$file]\n" unless -r $file;

  eval
    {
    require $file;
    };
  if( $@ )  
    {
    boom "error loading module file [$file] reason: $@";
    }

  boom "missing evolver:: namespace for user code [$file]"               unless exists $main::{ 'evolver::' };
  boom "missing evolver::mod:: namespace for user code [$file]"          unless exists $main::{ 'evolver::' }{ 'mod::' };
  boom "missing evolver::mod::${name}:: namespace for user code [$file]" unless exists $main::{ 'evolver::' }{ 'mod::' }{ $name . '::' };
  
  # TODO: check if main() exists
  my $code = \&{ "evolver::mod::${name}::main" };

  $CODE_CACHE{ $name } = $code;
  
  return $code->( $CONFIG, @_ );
}

### THE PREPROCESSOR #######################################################

sub preprocess_html
{
  my $text  = shift;
  my $path  = shift;
  my $level = shift() + 1;

  return $text if $level > 32;

  $text =~ s/\<([#%&*])([a-z0-9_\-]+)(\s+(.*?))?\>/preprocess_item( $1, $2, $4, $path, $level )/gie;
  $text =~ s/\[([#%&*])([a-z0-9_\-]+)(\s+(.*?))?\]/preprocess_item( $1, $2, $4, $path, $level )/gie;
  $text =~ s/ev_(src|href)=~/$1=$CONFIG->{ 'WWW' }/gi;

  return $text;
}

sub preprocess_item
{
  my $type  =    shift;
  my $name  = uc shift;
  my $args  =    shift;
  my $path  =    shift;
  my $level =    shift;
  
#print ">>> PP: [$type][$name][]\n";
  my $text;
  if( $type eq '#' )
    {
    $text = load_in_file( $path, $name, $level );
    }
  elsif( $type eq '%' )  
    {
    $text = $CONFIG->{ $name } if exists $CONFIG->{ $name };
    }
  elsif( $type eq '&' )  
    {
    $text = exec_mod( $name, { PATH => $path, ARGS => $args } );
    }
  elsif( $type eq '*' and $name eq 'NUM' )  
    {
    return num_fmt( $args );
    }
  elsif( $type eq '*' and $name eq 'SUBDIR' )  
    {
    return subdir_link_text( $path, $args );
    }
  elsif( $type eq '*' and $name eq 'SUBDIRS' )  
    {
    return subdirs_links( $path, $args );
    }
  else
    {
    die "invalid preprocess item [$type$name]\n";
    }
  return preprocess_html( $text, $path, $level );
}

sub load_in_file
{
  my $path  =    shift;
  my $name  = lc shift;
  my $level =    shift;

  my $text;

  my $p = $path;

  while( 4 )
    {
    my $file = "$IN/$p/$name.in";
    $file =~ s/\/+/\//g;
    if( -e "$file.html" )
      {
      $text = file_load( "$file.html" );
#print ">>> HTML: $file.html OK\n";
      last;
      }
    if( -e "$file.md" )
      {
      #$text = Text::Markdown::markdown( file_load( "$file.md" ) );
      $text = md2html( file_load( "$file.md" ) );
#print ">>> MARKDOWN: $file.md OK [$text]\n";
      last;
      }
    $p =~ s/\/[^\/]*$// or last;
    }

  return preprocess_html( $text, $path, $level );
}

### UTILS ####################################################################

sub num_fmt
{
  my $data = shift;
  $data = reverse $data;
  1 while $data =~ s/(\d\d\d)(\d)([^']*)$/$1'$2$3/;
  $data = reverse $data;
  return $data;
}

sub time_fmt
{
  my $t = shift;
  $t = localtime $t;
  $t =~ s/\d\d:\d\d:\d\d //;
  $t =~ s/ /&nbsp;/g;
  return $t;
}

sub subdirs_links
{
  my $path = shift;
  my $name = shift;

  my $text;
  $text .= subdir_link_text( $path, file_name_ext( $_ ) ) . "<hr>" for grep { -d } File::Glob::bsd_glob( "$IN/$path/$name" );
  
  return $text;
}

sub subdir_link_text
{
  my $path = shift;
  my $name = shift;

  my $dir   = "$IN/$path/$name";
  my $title = file_load( "$dir/_title.txt" );
  my $des   = file_load( "$dir/_des.txt" );
  my $icon;
  
  for my $it ( qw( png jpg gif ) )
    {
    $icon = "$name/_icon.$it" if -e "$dir/_icon.$it";
    }

  return "<table><tr><td width=1%><a href=$name><img src=$icon></a></td><td><a href=$name><h3>$title</h3></a><p>$des</td></tr></table>";
  
}

##############################################################################

sub preprocess_markdown
{
  my $text = shift;
  
  my @text = split /\n/, $text;
  
  my @res;
  
  while( @text )
    {
    my $line = shift @text;
    
    if( $line =~ /^\s*(#+)\s+(.*)/ )
      {
      my $h = length( $1 );
      $h = 6 if $h > 6;
      push @res, "<h$h>$2</h$h>";
      next;
      }
    elsif( $line =~ /^\s*$/ )
      {
      push @res, "<p>";
      next;
      }  
    elsif( $line =~ /^---+$/ )
      {
      push @res, "<hr>";
      next;
      }  
    elsif( $line =~ /^\s\s\s\s/ )
      {
      push @res, "<pre>\n";
      while(4)
        {
        $line = str_html_escape( $line );
        push @res, $line;
        $line = shift @text;
        next if $line =~ /^\s\s\s\s/;
        next if $line =~ /^\s*$/ and @text > 0;
        last;
        }
      unshift @text, $line;  
      push @res, "</pre>";
      next;
      }  
    else
      {
      push @res, $line;
      }  
    }

  for( @res )
    {
    s/\[([^\]]+)\]\(([^\)]+)\)/<a href=$2>$1<\/a>/gi;
    s/(?<!\=)(((http|https|ftp):\/\/|mailto:)[\S]+)/<a href=$1>$1<\/a>/gi;
    }

  return join "\n", @res;
}

##############################################################################

exit 11;
=pod
our %RESTRICTED;

our %STATS;

our %OPT  = load_hash( $opt_config );

# local directory options
our %LOPT = ();
our %LOPT_DEFAULTS = (
                     DIR_COLS   => 3,
                     GAL_COLS   => 5,
                     THUMB_SIZE => 128,
                     WEB_SIZE_W => 800,
                     WEB_SIZE_H => 600,
                     COPY_SIZE  => 1280,
                     );

my $stats_file = ".$opt_config.stats";
store( {}, $stats_file ) unless -e $stats_file;
my $stats = retrieve( $stats_file );
%STATS = %$stats if $stats;

my $ex = new HTML::Expander;

$SITE = uc $OPT{ 'SITE' } or die "SITE not specified inside config file\n";

# FIXME: expand in/out first!
chdir( $OPT{ 'IN' } ) or die "cannot chdir to $OPT{IN}\n";
mkpath( $OPT{ 'OUT' }, oct('0755') ) or die "cannot mkpath $OPT{OUT}\n";

my $style = $OPT{ 'STYLE' } || 'default.style';
die "cannot read style file: $style\n" unless -r $style;
$ex->mode_load( $style );
print "using style file: $style\n";

my %du;
for( `du -bL .` )
  {
  next unless /(\d+)\s+(.+)$/;
  $du{ $2 } = $1;
  }
my @dirs = reverse sort keys %du;

for( `du -abL $IN/.` )
  {
  # FIXME: tozi block se povtarq
  next unless /(\d+)\s+(.+)$/;
  $du{ $2 } = $1;
  }

@dirs = fnmatch_grep_list_v( \@IGNORE, \@dirs );

if( $opt_stats_up )
  {
  for( @dirs )
    {
    entry_changed( $_, '.' );
    }
  @dirs = ();
  }

$OPT{ 'EV_DATE' } = time_fmt( time() );
$OPT{ 'EV_REVISION' } = $REVISION;

%{ $ex->{'ENV'} } = ( %{ $ex->{'ENV'} }, %OPT );

print Dumper( $ex->{'ENV'} );

#---------------------------------------------------------------------------

entry_size_fill_cache( "$IN/." );

# figure what things are restricted
for my $path ( sort @dirs )
{
  %LOPT = load_lopt( $path );
  my $sites = uc $LOPT{ 'SITES' };

  if( $sites and index( ":$sites:", ":$SITE:" ) == -1 )
    {
    $RESTRICTED{ $path }++;
    print "site restriction, path ignored: [$path]\n";
    next;
    };
}

# now, produce the site...
DIR:
for my $path ( sort @dirs )
{
  last if $break_main_loop;

  next if $RESTRICTED{ $path };
  print "path: $path\n";
  next if $opt_force < 1 and ! entry_changed( $path, '.' );

  %LOPT = load_lopt( $path );

  mkpath( "$OUT/$path", oct('0755') ) unless -d "$OUT/$path";

  #my $newest = 0;
  my @entries = read_dir( $path );
  @entries = fnmatch_grep_list_v( \@IGNORE, \@entries );

  for my $e ( @entries )
    {
    last if $break_main_loop;

    my $i = "$IN/$path/$e";
    my $o = "$OUT/$path/$e";

    my $changed = entry_changed( $path, $e );
    #next if ! $opt_force and $mo >= $mi; # skip same files
    if( -d $i )
      {
      # FIXME: ?
      #print "       ====> $o\n";
      #mkpath( $o, oct('0755') );
      next;
      }
    elsif( $LOPT{ 'GALLERY' } and is_image( $e ) )
      {
      my $fo = "$OUT/$path/$e.html";
      my $force;
      $force = 1 unless -e $fo;
      my $text = process_gallery_image( $path, $e, $force );
      next unless $text;
      # FIXME: ugly! :/
      $OPT{ 'EV_IMAGE' } = $text;
      $text = find_text( $path, 'image' );
      save_file( $fo, $ex->expand( $text ) );
      delete $OPT{ 'EV_IMAGE' };
      }
    elsif( $changed )
      {
      print "$path/$e -- copy file\n";
      copy( $i, $o ) or print STDERR "WARNING: cannot copy $i to $o\n";
      post_process( $i, $o );
      }
    else
      {
      # nothing to do ...
      }
    }

  $OPT{ 'EV_PATH' } = $path;
  $OPT{ 'EV_PATH' } =~ s/^\.\///;

  next if $LOPT{ 'ASIS' };
  my $text;
  if( $LOPT{ 'DENY' } )
    {
    $text = find_text( $path, 'lost' );
    }
  elsif( $LOPT{ 'GALLERY' } )
    {
    $text = find_text( $path, 'gallery' );
    for my $entry ( qw( icon.jpg icon.png icon.gif ) )
      {
      my $src = "$IN/$path/$entry";
      next unless -e $src;
      next if ! entry_changed( $path, $entry );
      my $dst = "$OUT/$path/$entry";
      my $th_size  = $LOPT{ 'THUMB_SIZE'  };
      print "$path/$entry -- scaling  icon, $th_size...\n";
      scale_image( $src, $dst, $th_size, $th_size, 'ROTATE' );
      last;
      }
    }
  else
    {
    $text = find_text( $path, 'index' );
    }
  save_file( "$OUT/$path/index.html", $ex->expand( $text ) );
}

# post-processing STATS

$STATS{ 'CHANGED' } = merge( $STATS{ 'CHANGED_NEW' }, $STATS{ 'CHANGED' } );
delete $STATS{ 'CHANGED_NEW' };

# save stats
chdir( $startup_path );
print "saving STATS info to $stats_file\n";
store( \%STATS, $stats_file );
print "end.\n";


### FILE FINDER/LOADER #####################################################

sub find_text
{
  my $path = shift;
  my $name = lc shift;
  my $level =  shift;

  my $text = '';

  my $p = $path;

  while( 4 )
    {
    my $file = "$IN/$p/$name.in";
    $file =~ s/\/+/\//g;
    $text = load_file_ex( $file ) and last if -e $file;
    $p =~ s/\/[^\/]*$// or last;
    }
  if( $text =~ s/^#!WIKI[\n\r\s]+//i ) #
    {
    require CGI::Wiki::Formatter::UseMod;
    my $formatter = CGI::Wiki::Formatter::UseMod->new();
    $text = $formatter->format( $text );
    }

  return preprocess( $text, $path, $level + 1 );
}


### PATH INDEX HANDLER #####################################################

sub path_index
{
  my $path = shift;

  my @path_arr = split /\//, $path;
  shift @path_arr;
  my $path_add = $OPT{'WWW'} . '/';
  my $path_links = "<a href='$path_add'><img src=~/i/home24.png> <b>Home</b></a> / ";
  #my $file = pop @path_arr;
  for( @path_arr )
    {
    next unless $_;
    my $name = $_;
    $name =~ s/_/ /g;
    $name =~ s/\b(.)/uc $1/ge;
    $path_add .= "$_/";
    $path_links .= "<a href='$path_add'><img src=~/i/directory24.png> <b>$name</b></a> / ";
    }
  #$path_links .= "<black><b>\u$file</b></black>";

  return $path_links;
}

### DIRECTORY INDEX HANDLER ################################################

sub get_icon
{
  my $entry = shift;
  my $yy = 1 if -d "$IN/$entry";
  if( -d "$IN/$entry" )
    {
    my %lopt = load_lopt( $entry );
    return $GALICON if $lopt{ 'GALLERY' };
    return $lopt{ '!ICON' } || $DIRICON;
    }
  for my $k ( keys %ICONS )
    {
    next unless $entry =~ /\/([^\/]+)$/o;
    return $ICONS{ $k } if fnmatch( $k, $1, CASEFOLD => 1 );
    };
  return $UNKICON;
}

sub is_image
{
  my $entry = shift;
  return 0 if -d $entry;
  for my $k ( keys %IMAGES )
    {
    next unless $entry =~ /\/([^\/]+)$|^([^\/]+)$/o;
    return 1 if fnmatch( $k, $1 || $2, CASEFOLD => 1 );
    };
  return 0;
}

sub dir_index
{
  my $path = shift;

  my $text;
  my @entries;
  my @dirs;

  print "dir_index: $path\n";

  return if $LOPT{'NOINDEX'} or $LOPT{'DENY'};
  my $gallery = $LOPT{'GALLERY'};

  @entries = sort { entry_mtime( "$IN/$path/$b" ) <=> entry_mtime( "$IN/$path/$a" ) } read_files( "$IN/$path" );
  # remove non-visible entries
  @entries = fnmatch_grep_list_v( [ @IGNORE, @INDEX_IGNORE ], \@entries );
  # for galleries, remove images
  @entries = grep { ! is_image("$IN/$path/$_") } @entries if $gallery;
  my $newest = $entries[0];
  # remove site-restricted entries
  @dirs = grep { ! $RESTRICTED{ "$path/$_" } } read_dirs( "$IN/$path" );
  @dirs = fnmatch_grep_list_v( [ @IGNORE, @INDEX_IGNORE ], \@dirs );

  push @entries, @dirs;
  @entries = sort { -d "$IN/$path/$b" <=> -d "$IN/$path/$a" || $a cmp $b } @entries;
  my $enc = @entries;

  return undef unless $enc;

  my $dir_cols = $LOPT{ 'DIR_COLS' };

  my $all_size = 0;
  my $col = 0;

  $text .= "\n<!----- begin directory index: $path ---------------------------->\n";

  my $tr = 1;
  $text .= "<table class=view width=100% cellspacing=1>\n";
  $text .= "<tr class=tr$tr>";
  for my $entry (@entries)
    {
    next if -d "$path/$entry" and -e "$path/$entry/.deny";

    my $icon = "~/i/" . get_icon( "$path/$entry" );
    if( -d "$path/$entry" and ( -e "$path/$entry/icon.png" or -e "$path/$entry/icon.jpg" ))
      {
      for( qw( png jpg gif ) )
        {
        $icon = "$entry/icon.$_" if -e "$path/$entry/icon.$_";
        }
      }

    $icon = "<img src=$icon>";
    my $href = $entry;
    my $size = entry_size( "$IN/$path/$entry" );
       $all_size += $size;

    my $des = load_file( "$IN/$path/$entry/.des.txt" ) if -d "$IN/$path/$entry/";
       $des = "<hr noshade size=1>$des" if $des;

    my $sign = "<a href=$entry.asc><img src=~/i/emblem-nowrite.png title='This file is signed. Click here to view signature.'></a>" if -e "$IN/$path/$entry.asc";
    my $desc = "<a href=$entry.txt><img src=~/i/stock_zoom_fit_24.png title='Click here to see details.'></a>" if -e "$OUT/$path/$entry.txt";

    my $new = "<a href='$href' class=t><img src=~/i/warning24.png title='This is the newest file.'></a>" if $entry eq $newest;

    my $mtime = time_fmt( entry_mtime("$IN/$path/$entry") );
    my $width = int( 100 / $dir_cols );
    $tr = $col % $dir_cols ? 1 : 2;
    $text .=    "<td width=$width% align=left>
                   <table cellspacing=0 cellpadding=0>
                   <td>
                     <a href='$href' class=t>$icon</a>
                   </td>
                   <td>
                     $sign$desc$new <a href='$href' class=t>\u$entry</a><br>
                     <small>
                     $mtime<br>
                     [%NUM:$size] bytes
                     $des
                     </small>
                   </td>
                   </table>
                </td>";
    $text .= "</tr><tr class=tr$tr>\n" if ++$col % $dir_cols == 0;
    }
  $text .= "<td></td>" while $col++ % $dir_cols != 0;
  $text .= "</tr>";

  $text .= "</table>\n";

  $text .= "\n<!----- end   directory index: $path ---------------------------->\n";

  return $text;
}

### GALLERY INDEX ############################################################

sub gallery_index
{
  my $path = shift;

  my $text;
  my @entries;

  print "gallery_index: $path\n";

  return if -e $LOPT{'NOINDEX'} or $LOPT{'DENY'} or ! $LOPT{'GALLERY'};

  @entries = sort { entry_mtime( "$IN/$path/$b" ) <=> entry_mtime( "$IN/$path/$a" ) } grep { is_image( $_ ) } read_files( "$IN/$path" );
  my $newest = shift @entries;
  @entries = sort { $a cmp $b } grep { is_image( $_ ) } read_dir( "$IN/$path" );
  # remove non-visible entries
  @entries = fnmatch_grep_list_v( [ @IGNORE, @INDEX_IGNORE ], \@entries );

  my $gal_cols = $LOPT{ 'GAL_COLS' } || ( $LOPT{ 'DIR_COLS' } * 2 - 1 );

  #my $all_size = 0;
  my $col = 0;

  $text .= "\n<!----- begin gallery index: $path ------------------------------>\n";

  my $tr = 1;
  $text .= "<table class=view width=100% cellspacing=1>\n";
  #$text .= "<tr class=trh>
  #            <td colspan=$gal_cols align=left><img src=~/i/directory-photo.png height=24>Gallery</td>
  #          </tr>";

  $text .= "<tr class=tr$tr>";
  for my $entry (@entries)
    {
    #$all_size += entry_size( "$IN/$path/$entry" );
    my $new = " <img src=~/i/warning24.png>" if $entry eq $newest;
    $tr = $col % $gal_cols ? 1 : 2;
    $text .= gallery_image_td_format( $path, $entry, width => int( 100 / $gal_cols ), verbose => 1 );
    $text .= "</tr><tr class=tr$tr>\n" if ++$col % $gal_cols == 0;
    }
  $text .= "<td></td>" while $col++ % $gal_cols != 0;
  $text .= "</tr>";


  my $en = @entries;
  #$text .= "<tr class=trh>
  #            <td colspan=$gal_cols align=left><img src=~/i/irc.png> $en entries = [%NUM:$all_size] bytes</td>
  #          </tr>";
  $text .= "</table>\n";

  $text .= "\n<!----- end   gallery index: $path ------------------------------>\n";

  return $text;
}

#----------------------------------------------------------------------------

sub process_gallery_image
{
  my $path   = shift;
  my $entry  = shift;
  my $force  = shift;

  my $copy_size_w = $LOPT{ 'COPY_SIZE_W' } || $LOPT{ 'COPY_SIZE' };
  my $copy_size_h = $LOPT{ 'COPY_SIZE_H' } || $LOPT{ 'COPY_SIZE' };
  my $web_size_w  = $LOPT{ 'WEB_SIZE_W'  } || $LOPT{ 'WEB_SIZE' };
  my $web_size_h  = $LOPT{ 'WEB_SIZE_H'  } || $LOPT{ 'WEB_SIZE' };
  my $th_size     = $LOPT{ 'THUMB_SIZE'  };

  my $src = "$IN/$path/$entry";
  my $im  = "$OUT/$path/$entry";
  my $web = "$OUT/$path/web_$entry.jpg";
  my $tn  = "$OUT/$path/tn_$entry.jpg";

  my $changed_img = entry_changed( $path, $entry );
  my $changed_dir = entry_changed( $path, '.' );

  $changed_dir = 1 if $force > 0;
  $changed_img = 1 if $force > 1;

  if( $changed_img or ( ! -e $im ) )
    {
    #print "copy: $path/$entry -> $OUT\n";
    #copy( $src, $im ) or print STDERR "WARNING: cannot copy $src to $im\n";
    print "$path/$entry -- scaling  copy, $copy_size_w, $copy_size_h...\n";
    scale_image( $src, $im, $copy_size_w, $copy_size_h, 'ROTATE' );
    }
  if( $changed_img or ( ! -e $web ) )
    {
    print "$path/$entry -- scaling   web, $web_size_w, $web_size_h...\n";
    scale_image( $im, $web, $web_size_w, $web_size_h );
    }
  if( $changed_img or ( ! -e $tn ) )
    {
    print "$path/$entry -- scaling thumb, $th_size, $th_size...\n";
    scale_image( $web, $tn, $th_size );
    }

  # FIXME: trqbva da moje da se recreate-vat stranicite na snimkite...
  return if ! $changed_dir and ! $changed_img;

  print "$path/$entry -- image page [$changed_dir:$changed_img]\n";

  my @images;
  my %images;
  @images = sort { $a cmp $b } grep { is_image( $_ ) } read_dir( "$IN/$path" );
  # remove non-visible entries
  @images = fnmatch_grep_list_v( [ @IGNORE, @INDEX_IGNORE ], \@images );
  my $c = 0;
  $images{ $_ } = $c++ for @images;

  my $gal_cols = $LOPT{ 'GAL_COLS' } || ( $LOPT{ 'DIR_COLS' } * 2 - 1 );
  my $nav_cols = $LOPT{ 'NAV_COLS' } || $gal_cols;

  my $gal_width = int( 100 / $gal_cols );

  my $c = $images{ $entry };
  my $l = $c - int( ( $nav_cols - 1 ) / 2 );
  my $r = $c + int( ( $nav_cols - 1 ) / 2 );

  my $exif = entry_exif( $src );
  my $note = load_file( "$src.note" );
  my $exif_text;

  if( $exif )
    {
    $exif_text .= "<table class=view width=50% cellspacing=1>";
    $exif_text .= "<tr class=trn><td align=center><a href=# onClick='javascript:swapSee(\"exif-info\");return false;'><b>image information</b></a></td>";
    $exif_text .= "</table>";
    $exif_text .= "<table class=view id=exif-info width=50% cellspacing=1>";
    my $c;
    # for( sort keys %$exif )
    for( @EXIF_TAGS )
      {
      $c = $c == 1 ? 2 : 1;
      $exif_text .= "<tr class=tr$c><td>$_</td><td align=right>$$exif{$_}</td></tr>\n";
      }
    $exif_text .= "</table>";
    }

  my $text;

  my @itab;

  $text .= "<div align=center>";
  $text .= "<table><tr><td valign=top width=1%>";
  $text .= "<table class=view width=100% cellspacing=1>\n";
  $text .= "<tr class=trn>";
  for( $l .. $r )
    {
    my $e  = $_ < 0 ? '' : $images[ $_ ];
    my $ef = $_ < 1 ? '' : $images[ $_-1 ];
    my $el = $_ < 0 ? '' : $images[ $_+1 ];
    my $bg = "background=#ff0000" if $c == $_;
    if( $e )
      {
      my $first = 1 if $ef and $_ == $l;
      my $last  = 1 if $el and $_ == $r;
      push @itab, gallery_navigation_td_format( $path, $e, first => $first, last => $last, class => $_ == ( $l + $r ) / 2 ? 'current' : '' );
      }
    else
      {
      push @itab, "<td width=$gal_width% align=center><img src=~/i/empty.png width=$th_size height=$th_size></td>";
      }
    }
  $text .= join '</tr><tr class=trn>', @itab;
  $text .= "</tr></table>\n";

  $text .= "</td><td valign=top align=center>";
  $text .= "<box><pre><img src=~/i/empty.png width=800 height=1><br>$note</pre></box><p>\n" if $note;
  $text .= "<a name=#photo><box><a href=$entry><img src=web_$entry.jpg alt=$entry title=$entry></a></box>\n";
  $text .= "<br>$exif_text";
  $text .= "</td></tr></table>";
  $text .= "</div>";

  return $text;
}

sub gallery_image_td_format
{
  my $path  = shift;
  my $entry = shift;
  my %opt = @_;

  my $th_size = $LOPT{ 'THUMB_SIZE' };

  my $new   = $opt{ 'new' };
  my $hintl = $opt{ 'hintl' };
  my $hintr = $opt{ 'hintr' };
  my $hintu = $opt{ 'hintu' };
  my $hintd = $opt{ 'hintd' };
  my $width = $opt{ 'width' };
  my $class = $opt{ 'class' };

  $hintu = "$hintu<br>" if $hintu;
  $hintd = "<br>$hintd" if $hintd;
  $class = "class=$class" if $class;

  my $size  = entry_size( "$OUT/$path/$entry" );
  my $mtime = time_fmt( entry_mtime( "$IN/$path/$entry" ) );
  my $note_icon = "<img src=~/i/image-note.png>" if -e "$path/$entry.note";
  #my $verbose = "<br><b>\u$entry</b><br>
  my $verbose = "<table border=0>
                 <tr>
                   <td>$note_icon$new</td>
                   <td><small>$mtime<br>[%NUM:$size] bytes</small></td>
                 </tr>
                 </table>" if $opt{ 'verbose' };

  # <img src=~/i/empty.png width=$th_size height=1>
  return    "<td align=center width=$width% $class>
                <a href='$entry.html' class=t>$hintu$hintl<img src=tn_$entry.jpg>$hintr$verbose$hintd
             </td>";
}

sub gallery_navigation_td_format
{
  my $path  = shift;
  my $entry = shift;
  my %opt = @_;

  my $th_size = $LOPT{ 'THUMB_SIZE' } + 10;

  my $class = $opt{ 'class' };

  my $hf = "<img src=~/i/stock_media_play_up_24.png><br>"       if $opt{ 'first' };
  my $hl = "<br><img src=~/i/stock_media_play_down_24.png>"     if $opt{ 'last'  };

  $class = "class=$class" if $class;

  return    "<td align=center height=${th_size}px width=${th_size}px $class>
                $hf<a href='$entry.html' class=t><img src=tn_$entry.jpg>$hl
             </td>";
}

### MAIN TEXT HANDLER ########################################################

sub main_text
{
  my $path = shift;

  my $inside;

  if( -e "$path/text.in" )
    {
    return find_text( $path, 'text');
    }
  elsif( -e "$path/README" )
    {
    my $text = load_file( "$path/README" );
    $text =~ s/>/&gt;/go;
    $text =~ s/</&lt;/go;

    $text =~ s/(mailto:\S+)/<a href=$1>$1<\/a>/gio;
    $text =~ s/((http|ftp):\/\/\S+)/<a href=$1>$1<\/a>/gio;

    my $contents;

    my $top = "<a href=#top><img src=~/i/top.gif></a>";
    my @text = split /\n/, $text;
    my $c = 0;
    for( @text )
      {
      $c++;
      s/^([A-Z][A-Z\s]+)$/<a name=$c><h1>$top $1<\/h1>/ and $contents .= "<a href=#$c><b>$1</b></a><br>" and next;
      $c++;
      s/^(\s+[A-Z][A-Z\s]+)$/<a name=$c><h2>$top $1<\/h2>/ and $contents .= "<a href=#$c>$1</a><br>" and next;
      }

    $contents = "<h1>CONTENTS</h1><blockquote>$contents</blockquote><hr>" if $contents;
    $text = $contents . join "\n", @text;
    $inside = "<pre>$text</pre>";
    }
  elsif( -e "$path/README.wiki" )
    {
    require CGI::Wiki::Formatter::UseMod;
    # Instantiate - see below for parameter details.
    my $formatter = CGI::Wiki::Formatter::UseMod->new();
    my $text = load_file( "$path/README.wiki" );
    $text = $formatter->format( $text );

    $inside = "$text";
    }
  else
    {
    $inside = '<code>no additional information available...</code>';
    $inside = undef;
    }

  return undef unless $inside;

  my $text = "<table width=100% class=view cellspacing=1>
              <tr class=trn><td width=100%>$inside</td></tr>
              </table>";

  return $text;
}

### POST PROCESS ###########################################################

sub post_process
{
  my $i = shift;
  my $o = shift;

  if( $o =~ /\.tar$/ )
    {
    system( "tar tvf '$o' > '$o.txt' " );
    }
  elsif( $o =~ /\.tar\.gz$/ )
    {
    system( "tar tzvf '$o' > '$o.txt' " );
    }
  elsif( $o =~ /\.tar\.bz2$/ )
    {
    system( "bunzip2 -dc '$o' | tar tvf - > '$o.txt' " );
    }
}

### SPECIFIC HELPERS #######################################################

sub entry_size_fill_cache
{
  my $s = shift;
  return $du{ $s } if exists $du{ $s };
  my @t = `du -b $s`;
  chomp @t;
  for( @t )
    {
    next unless /^(\d+)\s+(.+)/;
    $du{ $2 } = $1;
    }
}

our %SIZE_CACHE;
sub entry_size
{
  my $s = shift;
  return $du{ $s } if $du{ $s };
  return $SIZE_CACHE{ $s } || ( $SIZE_CACHE{ $s } = (stat($s))[7] );
}

our %MTIME_CACHE;
sub entry_mtime
{
  my $s = shift;
  return $MTIME_CACHE{ $s } || ( $MTIME_CACHE{ $s } = (stat($s))[9] );
}

our %EXIF_CACHE;
sub entry_exif
{
  my $src = shift;
  return $EXIF_CACHE{ $src } if $EXIF_CACHE{ $src };
  my $exif = $src =~ /\.jpe?g$/io ? Image::EXIF->new( $src )->get_image_info() : undef;
  $EXIF_CACHE{ $src } = $exif;
  return $exif;
}

sub entry_changed
{
  my $path  = shift;
  my $entry = shift;

  my $e  = "$path/$entry";
  my $fi = "$IN/$e";
  my $fo = "$OUT/$e";

  unless( -e $fo )
    {
    $STATS{ 'CHANGED' }{ $e } = 1;
    }

  if( $STATS{ 'CHANGED' }{ $e } and $STATS{ 'CHANGED_NEW' }{ $e } )
    {
    return 1 if $STATS{ 'CHANGED' }{ $e } ne $STATS{ 'CHANGED_NEW' }{ $e };
    }

  my $o; # old/previous time/stat
  my $n; # new time/stat

  if( -d $fi)
    {
    # dir
    $n = `ls -l $fi | md5sum -`;
    $n =~ s/[\s\r\n\-]+$//;
    }
  else
    {
    # file
    $n = entry_mtime( $fi );
    }
  $o = $STATS{ 'CHANGED' }{ $e };
  $STATS{ 'CHANGED_NEW' }{ $e } = $n;

  die "empty N! [$n] for $path/$entry\n" unless $n;

  my $changed = $o eq $n ? 0 : 1;
  print "DEBUG: $path/$entry O[$o]\n" if $DEBUG;
  print "DEBUG: $path/$entry N[$n] => $changed\n" if $DEBUG;
  return $changed;
}

sub read_dir
{
  my $path = shift;
  my $DIR;
  opendir $DIR, $path;
  my @e = readdir $DIR;
  closedir $DIR;
  # leave .in's last ...
  @e = sort { $a =~ /\.in$/i <=> $b =~ /\.in$/i } grep { $_ ne '.' and $_ ne '..' } @e;
  return @e;
}

sub read_files
{
  return grep { ! -d "$_[0]/$_" } read_dir( $_[0] );
}

sub read_dirs
{
  return grep {   -d "$_[0]/$_" } read_dir( $_[0] );
}

### GENERIC HELPERS ########################################################

sub mkpath
{
  my $path = shift;
  my $mask = shift;
  my $abs;

  $path =~ s/\/+$/\//o;
  $abs = '/' if $path =~ s/^\/+//o;

  my @path = split /\/+/, $path;

  $path = $abs;
  for my $p ( @path )
    {
    $path .= "$p/";
    next if -d $path;
    mkdir( $path, $mask ) or return 0;
    }
  return 1;
}

sub fnmatch
{
  my $pattern = shift;
  my $name    = shift;
  my %opt     = @_;

  if( $opt{ 'CASEFOLD' } or $opt{ 'NOCASE' } )
    {
    $pattern = uc $pattern;
    $name    = uc $name;
    }

  if( $name =~ /\/([^\/]+)$/ )
    {
    $name = $1;
    }

  $pattern =~ s/\./\\./go;
  $pattern =~ s/\?/./go;
  $pattern =~ s/\*/.*?/go;
  $pattern = "^$pattern\$";
  #print ">>>>>>>>>>>>>>>>>> [$name] =~ [$pattern]\n";
  return $name =~ /$pattern/;
}

sub fnmatch_grep_list
{
  my $mask = shift;
  my $list = shift;
  my %opt  = @_;
  my @res;

  for my $e ( @$list )
    {
    my $in = $opt{ 'DEFAULT' } || 0;

    $in = 1 if $opt{ 'REMOVE' };
    $in = 0 if $opt{ 'GREP' };

    for my $m ( @$mask )
      {
      next unless fnmatch( $m, $e, %opt );
      $in = ! $in;
      last;
      }

    next unless $in;
    push @res, $e;
    }

  return @res;
}

sub fnmatch_grep_list_v
{
  return fnmatch_grep_list( @_, REMOVE => 1 );
}


sub load_file_ex
{
  my $s = shift;
  $s = "$s |" if -x $s;
  return load_file( $s );
}

sub load_file
{
  my $file = shift;
  open( my $i, $file ) or return undef;
  local $/ = undef;
  my $s = <$i>;
  close $i;
  return $s;
}

sub save_file
{
  my $file = shift;
  open( my $o, ">$file" ) or return undef;
  print $o @_;
  close( $o );
  return 1;
}

sub load_hash
{
  my $file = shift;
  my %opt = @_;
  my %h;
  for( split( /[\n\r]+/, load_file( $file ) ) )
    {
    next unless /(.+?)(?<!\\)=(.*)/;
    my $k = $1;
    my $v = $2;
    $k =~ s/\\(.)/$1/go;
    $v =~ s/\\(.)/$1/go;
    $k = uc $k if $opt{ 'KEY_UC' };
    $k = lc $k if $opt{ 'KEY_LC' };
    $v = uc $v if $opt{ 'VAL_UC' };
    $v = lc $v if $opt{ 'VAL_LC' };
    $h{ $k } = $v;
    }
  return wantarray ? %h : \%h;
}

sub save_hash
{
  my $file = shift;
  my $hr = shift;
  open( my $o, ">$file" ) or return undef;
  while( my ( $k, $v ) = each %$hr )
    {
    $k =~ s/=/\\=/g;
    print $o "$k=$v\n";
    }
  close( $o );
  return 1;
}

### IMAGE FUNCTIONS ########################################################

sub scale_image
{
  my $i = shift; # input image file name
  my $o = shift; # output image file name
  my $w = shift; # target width
  my $h = shift; # target height
  my $a = shift; # autorotate, true/false

  $h = $w unless $h; # when optional height is omitted

  my $im = Image::Magick->new();
  $im->Read( $i );

  if( $a )
    {
    my $exif = entry_exif( $i );
    if( $exif )
      {
      my $deg = $ROTATION{ $exif->{ 'Image Orientation' } };
      if( $deg )
        {
        print "$i -- rotating image at $deg degrees\n";
        $im->Rotate( degrees => $deg );
        }
      }
    }

  my ( $iw, $ih ) = $im->GetAttribute( 'columns', 'rows' );
  if( $iw <= $w and $ih <= $h )
    {
    print "$i -- image smaller than ${w}x${h}, not scaling\n";
    }
  else
    {
    $im->AspectScale( width => $w, height => $h );
    }
  $im->Write( $o );
}

### Image::Magick ##########################################################

package Image::Magick;

sub AspectScale
{
  my $self = shift;
  my %opt = @_;
  my $w = $opt{ 'width'  };
  my $h = $opt{ 'height' };

  my ( $ow, $oh ) = $self->Get( 'width', 'height' );

  my $aspect = $ow / $oh;

  if ( $ow > $oh )
    {
    $h = int( $w / $aspect );
    }
  else
    {
    $w = int( $h * $aspect );
    }

  $opt{ 'width'  } = $w;
  $opt{ 'height' } = $h;

  $self->Scale( %opt );
}

=cut

############################################################################

# EOF

package evolver::mod::ls;
use strict;
use Data::Dumper;
use Data::Tools;
use Tie::IxHash;
use POSIX;

my %FILE_TYPES;
tie %FILE_TYPES, 'Tie::IxHash';
%FILE_TYPES = (
               # show the following
               'AUTHORS(\.txt)?'        => 'authors48.png',
               '\.tar\.(gz|bz|bz2|xz)$' => 'box-package.png',
               '\.zip$'                 => 'box-package.png',
               '\.txt$'                 => 'textfile.png',
               '\.(jpg|jpeg|png|gif)$'  => 'image-generic.png',
               '^LICENSE$'              => 'copying.png',
               '^COPYING$'              => 'copying.png',
               '^CHANGELOG$'            => 'text-history.png',
               '^HISTORY$'              => 'text-history.png',
               '^GIT_HISTORY$'          => 'text-history.png',
               '^README$'               => 'news.png',
               '^NEWS$'                 => 'news.png',
               '^FAQ$'                  => 'faq.png',
               '\.lsm$'                 => 'linux-tux.png',
               );                              

my %IGNORE_TYPES;
%IGNORE_TYPES = (
               # skip these
               '^_'                     => undef,
               '\.in\.(html|fdoc)$'     => undef,
               '\.tar\.gz\.txt$'        => undef,
               '\.tar\.gz\.asc$'        => undef,
               );

my %FILTER_TYPES = (
               'F'     => 'F',
               'FILE'  => 'F',
               'FILES' => 'F',
               'D'     => 'D',
               'DIR'   => 'D',
               'DIRS'  => 'D',
               '*'     => 'A',
               'A'     => 'A',
               'FD'    => 'A',
               'DF'    => 'A',
               'ALL'   => 'A',
               );


sub main
{
  my $cfg = shift;
  my $env = shift;
  
  my $lopt = $env->{ 'LOPT' } || {};
  my $path = $env->{ 'PATH' };
  my @args = split /\s+/, $env->{ 'ARGS' };

  my $in  = $cfg->{ 'IN' } . "/$path/";
  my $inl = length( $in );

  my $text;

  $text .= "<table class=ls>";

  my $filter_type = $FILTER_TYPES{ uc shift @args };

  if( exists $lopt->{ "LS_$filter_type" } and $lopt->{ "LS_$filter_type" } )
    {
    @args = split /\s+/, $lopt->{ "LS_$filter_type" };
    }

  my @e;

  push @e, glob "$in$_" for @args;
  @e = list_uniq @e;

  @e = grep {   -d } @e if $filter_type eq 'D';
  @e = grep { ! -d } @e if $filter_type eq 'F';
  # A(ll) does nothing :)

  my $nt; # newest time
  my $ne; # newest entry
  for my $e ( @e )
    {
    my $t = (stat( $e ))[8];
    next unless $t > $nt;
    $nt = $t;
    $ne = $e;
    }
  
  my $c;
  
  ENTRY:
  for my $e ( @e )
    {
    my $ee = substr( $e, $inl );

    for my $k ( keys %IGNORE_TYPES )
      {
      my $v = $FILE_TYPES{ $k };
      next ENTRY if $ee =~ /$k/i;
      }

    my $s = str_num_comma( -s $e );
    my $t = POSIX::strftime( "%b %d, %Y", localtime( (stat( $e ))[8] ) ); # <sup><small>%H:%M</small></sup>

    $c = ( $c == 1 ) + 1;
    $text .= "<tr class=ls$c>";

    my $icon_type = undef;

    my $ees;  # entry name string (with decorations)
    my $eed;  # entry description
    my $ss  = "$s bytes";
    if( -d $e )
      {
      $icon_type = "<img src=~/i/directory.png>";
      
      for my $it ( qw( png jpg gif ) )
        {
        next unless -e "$e/_icon.$it";
        $icon_type = "<img src=$ee/_icon.$it>";
        last;
        }

      $icon_type ||= "<img src=~/i/directory.png>";

      ( $ees, $eed ) = get_readme_title_des( "$e/README" );
      
      $ees ||= file_load( "$e/_title.txt" ) || "[".uc( clean_dir_title( $ee ) )."]";
      $eed ||= file_load( "$e/_des.txt" );
      
        # FIXME: TODO: rich-text function
        $eed =~ s/\*\*(.+?)\*\*/<b>$1<\/b>/g;

      
      $eed = "<br><div class=lsdes>$eed</div>";
      $ss = "<b>[DIRECTORY]</b>";
      }
    else
      {
      $ees = clean_dir_title( $ee );
      for my $k ( keys %FILE_TYPES )
        {
        my $v = $FILE_TYPES{ $k };
        next unless $ee =~ /$k/i;
        last unless $v;
        $icon_type = "<img src=~/i/$v>";
        last;
        }
      $icon_type ||= "<img src=~/i/unknown.png>";
      }  
    

    # TODO: list file name, size, modify time, signature

    my $extra;
    
    $extra .= "<a class=ls href=$ee.txt title='See details about this file'><img src=~/i/ls-des.png></a>"     if -e "$e.txt";
    $extra .= "<a class=ls href=$ee.asc title='See GPG signature for this file'><img src=~/i/ls-sig.png></a>" if -e "$e.asc";
    my $new = "<a class=ls href=$ee     title='Most recent entry!'><img src=~/i/ls-new.png></a>"              if $e eq $ne;

    $text .= "<td>$icon_type</td><td width=100%><a class=ls href=$ee>$ees</a> $new$eed</td><td align=right>$ss<br>$t</td><td>$extra</td>\n";


    $text .= "</tr>";
    }

  $text .= "</table>";

  return $text;
}

sub clean_dir_title
{
  my $s = shift;
  
  $s =~ s/_/ /g;
  
  return $s;
}

sub get_readme_title_des
{
  my $fn = shift;

  my $title;
  my $des;
  for( split( /\n/, file_load( $fn ) ) )
    {
    $title = $1 if /^\s*\@TITLE\s+(.*)/i;
    $des   = $1 if /^\s*\@DES\s+(.*)/i;
    }
  return ( $title, $des );
}

1;

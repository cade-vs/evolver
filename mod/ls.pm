package evolver::mod::ls;
use strict;
use Data::Dumper;
use Data::Tools;
use POSIX;

my %FILE_TYPES = (
                 '\.tar\.(gz|bz|bz2|xz)$' => 'package-x-generic.png',
                 '\.zip$'                 => 'package-x-generic.png',
                 '\.txt$'                 => 'text-x-generic.png',
                 '^LICENSE$'              => 'law-x-generic.png',
                 '^COPYING$'              => 'law-x-generic.png',
                 '^CHANGELOG$'            => 'start-here.png',
                 '^HISTORY$'              => 'start-here.png',
                 '^README$'               => 'internet-news-reader.png',
                 '^NEWS$'                 => 'internet-news-reader.png',
                 );


sub main
{
  my $cfg = shift;
  my $env = shift;
  
  my $path = $env->{ 'PATH' };
  my $args = $env->{ 'ARGS' };

  my $in  = $cfg->{ 'IN' } . "/$path/";
  my $inl = length( $in );

  my $text;
  
  $text .= "<table class=ls>";

  my @e;

  push @e, glob "$in$_" for split /\s+/, $args;
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
  for my $e ( @e )
    {
    my $ee = substr( $e, $inl );

    my $s = str_num_comma( -s $e );
    my $t = POSIX::strftime( "%b %d, %Y", localtime( (stat( $e ))[8] ) );

    $c = ( $c == 1 ) + 1;
    $text .= "<tr class=ls$c>";

    my $icon_type = '&nbsp;';
    
    for my $k ( keys %FILE_TYPES )
      {
      my $v = $FILE_TYPES{ $k };
      next unless $ee =~ /$k/i;
      $icon_type = "<img src=~/i/$v>";
      last;
      }
    
    # TODO: list file name, size, modify time, signature

    my $extra;
    
    $extra .= "<a class=ls href=$ee.asc title='See GPG signature for this file'><img src=~/i/ls-sig.png></a>" if -e "$e.asc";
    $extra .= "<a class=ls href=$ee.txt title='See details about this file'><img src=~/i/ls-des.png></a>"     if -e "$e.txt";
    my $new = "<a class=ls href=$ee     title='Most recent file!'><img src=~/i/ls-new.png></a>"     if $e eq $ne;

    $text .= "<td>$icon_type</td><td width=100%><a class=ls href=$ee>$ee $new</a></td><td align=right>$s bytes<br>$t</td><td>$extra</td>\n";


    $text .= "</tr>";
    }

  $text .= "</table>";

  return $text;
}

1;

package evolver::mod::lsd;
use strict;
use Data::Dumper;
use Data::Tools;

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

  my @d;

  push @d, grep { -d } glob "$in$_" for split /\s+/, $args;
  @d = list_uniq @d;

  my $text;
  for my $d ( @d )
    {
    my $dd = substr( $d, $inl );
    
    my $dir   = "$in/$dd";

    next unless $dir; # FIXME: ???

    my $title = file_load( "$dir/_title.txt" ) || get_readme_title( "$dir/README" ) || clean_dir_title( $dd );
    my $des   = file_load( "$dir/_des.txt" );
    my $icon;
    
    for my $it ( qw( png jpg gif ) )
      {
      next unless -e "$in/$dd/_icon.$it";
      $icon = "<img src=$dd/_icon.$it>";
      last;
      }

    $icon ||= "<img src=~/i/directory.png>";

    $text .= "
              <table cellpadding=0>
              <tr>
                <td width=1% class=index-left valign=top rowspan=2>
                  <a href=$dd class=icon>$icon</a>
                </td>
                <td valign=top>
                    <table class=index-right height=100%>
                    <tr>
                      <td class=index-title valign=top>
                        <a href=$dd><h2 class=index>$title</h2></a>
                      </td>
                    </tr>
                    <tr height=100%>
                      <td class=index-des>
                        $des
                      </td>
                    </tr>
                    </table>
                </td>
              </tr>
              </table>
             ";
    }
  
  return $text;
}


sub clean_dir_title
{
  my $s = shift;
  
  $s =~ s/_/ /g;
  
  return $s;
}

sub get_readme_title
{
  my $fn = shift;

  my $title = ( split( /\n/, file_load( $fn ) ) )[0];

  $title =~ s/^\s*=\s*//;
  
  return $title;
}

1;

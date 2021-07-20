package evolver::mod::fdoc;
use strict;
use Data::Dumper;
use Data::Tools;

sub main
{
  my $cfg = shift;
  my $env = shift;
  
  my $path = $env->{ 'PATH' };
  my $args = $env->{ 'ARGS' };

  my $in  = $cfg->{ 'IN' } . "/$path/";

  my @fdocs = glob( "$in/*.in.fdoc" );
  my $in_doc_fname = @fdocs == 1 ? shift( @fdocs ) : "$in/article.in.fdoc";

  my @data = split /\n/, ( file_load( $in_doc_fname ) | file_load( "$in/README" ) );
  $_ .= "\n" for @data;

  my $text;
  
  my @toc;
  my $begin;
  
  my $head_count = 0;
  while( @data )
    {
    $_ = shift @data;
    if( /^\s*\@LS\s+(.*)/i )
      {
      $text .= "[&ls $1]";
      next;
      }
    if( /^\s*\@IMG\s+(\S+)/i )
      {
      $text .= "<div class=article-image><img src=$1><\/div>";
      next;
      }
    if( /^\s*\@TOC/i )
      {
      $text .= '@@@TOC@@@';
      next;
      }
    if( /^\s*\@TITLE\s+(.*)/i )  
      {
      $main::VARS{ 'TITLE' } = $1;
      next;
      }
    if( /^\s*\@/i )  
      {
      next;
      }

    next if ! $begin and /^\s*$/;
    $begin++;
    
    if( /^(=+)\s*(.*)/ or /^([A-Z0-9]+?[\sA-Z0-9]+)$/ )
      {
      my $ll = length( $1 ) || 2;
      my $head = $2;
      $head_count++;

      unless( $ll == 1 and $head_count == 1 )
        {
        # first H1 heading in a file will not go into the table of contents (TOC)
        my $anchor = $head;
        $anchor =~ s/[^a-z_0-9]/_/gi; 
        push @toc, "<a href=#$anchor>$head</a>" if $ll <= 2;
        $text .= "<a name=$anchor></a>";
        }

      my $back_top = "<td><a href=#top alt='Back to top of the page'><img class=icon src=~/i/up_arrow_24.png></a></td>" if $head_count > 1;
      $text .= "<h$ll class=article><table><tr><td width=100%>$head</td>$back_top</tr></table></h$ll>\n";
      
      next;
      }

    if( /^(  +)(.*)/ )
      {
      my $strip_len = length( $1 );
      $text .= "<pre class=article>";
      $text .= str_html_escape( substr( $_, $strip_len  ) );
      while( @data )
        {
        $_ = shift @data;
        if( ! /^  +|^$/ )
          {
          unshift @data, $_;
          last;
          }
        $text .= str_html_escape( substr( $_, $strip_len  ) );  
        }
      #chomp( $text );  
      $text .= "</pre>";
      next;  
      }
    
    $text .= "<p>" if /^\s*$/;  
    $text .= str_html_escape( $_ );  
    }


  # inject toc
  $text =~ s/\@\@\@TOC\@\@\@/"<div class=article-toc>" . join(' | ',@toc) . "<\/div>"/e;
  
  # decoration and hyperlinks
  $text =~ s/\[\[([^\s\]]+)( ([^\]]+)\]\])/"<a href='$1'>".($3||$1)."<\/a>"/ge;
  $text =~ s/(\s|^)((https?:\/\/|mailto:)[^\s<>]+)/$1<a href="$2">$2<\/a>/g;
  $text =~ s/\*\*(.+?)\*\*/<b>$1<\/b>/g;
  
  return $text;
}


1;

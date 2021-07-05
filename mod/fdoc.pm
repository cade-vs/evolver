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
  my $margin = 0;
  
  my $head_count = 0;
  while( @data )
    {
    $_ = shift @data;
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

      $text .= "<h$ll class=article>$head</h$ll>\n";
      
      next;
      }

    if( /^  +(.*)/ )
      {
      $text .= "<pre class=article>\n\n";
      $text .= $_;
      while( @data )
        {
        $_ = shift @data;
        if( ! /^  +|^$/ )
          {
          unshift @data, $_;
          last;
          }
        $text .= str_html_escape( $_ );  
        }
      $text .= "</pre>";
      next;  
      }
    
    $text .= "<p>" if /^\s*$/;  
    $text .= str_html_escape( $_ );  
    }


  $text =~ s/\@TOC\@/"<div class=article-toc>" . join(' | ',@toc) . "<\/div>"/e;
  $text =~ s/\@IMG:([^@]+)\@/<div class=article-image><img src=$1><\/div>/g;
  $text =~ s/\@LS:([^@]+)\@/[&ls $1]/g;
  $text =~ s/((https?:\/\/|mailto:)\S+)/<a href="$1">$1<\/a>/g;
  $text =~ s/\*\*(.+?)\*\*/<b>$1<\/b>/g;
  
  return $text;
}


1;

package evolver::mod::path;
use strict;

sub main
{
  my $cfg = shift;
  my $env = shift;

  my $path = $env->{ 'PATH' };

  my @path = split /\//, $path;
  shift @path;
  
  my $text;

  # $text .= " <a class=main-menu-path href=~/>HOME</a> / ";
  $path = undef;
  for my $p ( @path )
    {
    $path .= "$p/";
    $p = uc $p;
    $text .= " &raquo; <a class=main-menu href=~/$path>$p</a>";
    }
  
  return $text;
}

1;

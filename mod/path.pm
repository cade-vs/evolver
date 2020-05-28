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

  $text .= " <a class=main-menu-path href=~/>HOME</a> / ";

  $path = undef;
  for my $p ( @path )
    {
    $path .= "$p/";
    $text .= " <a class=main-menu-path href=~/$path>$p</a> / ";
    }
  
  return $text;
}

1;

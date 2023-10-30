#!/usr/bin/env perl

use v5.36;
use utf8;
use strictures 2; # nice `use strict`, `use warnings` defaults
use open qw(:utf8); # try to use Perl's internal Unicode encoding for everything
BEGIN{$diagnostics::PRETTY = 1} # a bit noisy, but somewhat informative
use diagnostics -verbose;

# Carp
    use Carp;
    use Carp::Assert;
# filepath functions
    use Cwd qw(abs_path);
    use File::Basename qw(basename dirname);
    use File::Spec;
# misc file utilities
    use File::Temp;
    use File::Slurp;
    use YAML::XS;
# misc scripting IO utilities
    use IO::Prompter;
    # `capture_stdout` for backticks w/o shell (escaping issues)
    use Capture::Tiny qw(:all);
    # for more complicated stuff
    # eg timeout, redirection
    use IPC::Run qw(run);
    use IPC::Cmd qw(can_run);
# option/arg handling
    use Getopt::Long qw(:config gnu_getopt auto_version); # auto_help not the greatest
    use Pod::Usage;
# use local modules
    use lib (
        dirname(abs_path($0)),
        ); # https://stackoverflow.com/a/46550384
 
# turn on features
    use builtin qw(true false is_bool reftype);
    no warnings 'experimental::builtin';
    use feature 'try';
    no warnings 'experimental::try';

    our $VERSION = version->declare('v2023.10.29');
# end prelude
use Data::Dumper;

sub subst($env, @xs){
    @xs = grep defined, @xs;
    return map {
        $_ =~ s/\$(\S+)/$env->{$1}/;
        $_
    } @xs;
}
sub proc_eval($proc, $args, @program){
    my @args = grep defined, @$args;
    say "$proc: @args";
}

# read YAML program
my %program = %{YAML::XS::LoadFile $ARGV[0]};
# require 'main' top level key
my @main = @{$program{main}};
delete $program{main};
# main's script variables
my %env;
# main should be a sequence of commands, then a key-value describing the procs and their arguments
# NOTE: for now, we assume the sequence of commands are just "@arg n $var" builtins
for my $line (@main){
    if(defined(reftype $line)){ # must be procs and args
        if(reftype $line eq 'HASH'){
            say STDERR "starting main with %env:";
            say STDERR YAML::XS::Dump(\%env) . '...';
            my %exec = %{$line};
            my @child_pids;
            for my $proc (keys %exec){
                my $pid = fork;
                if(defined $pid){
                    if($pid){ # parent
                        push @child_pids, $pid;
                        next;
                    }
                    else{ # child
                        # TODO: $exec{proc} should be an array, but I don't need it right now
                        # we're just going to support single strings for now
                        &proc_eval($proc, [subst(\%env, $exec{$proc})], @{$program{$proc}});
                        exit 0;
                    }
                }
                else{
                    croak "fork failed. $!";
                }
            }
        }
        else{
            croak "main should be a hash of procs";
        }
    }
    elsif($line =~ m/^\@arg\s+(\d+)\s+\$(\S+)$/){ # else @arg builtin
        say STDERR "$ARGV[1 + $1] -> \$$2";
        $env{$2} = $ARGV[1 + $1];
    }
    else{
        croak "main is malformed at line: $line";
    }
}
# return EXIT_SUCCESS
0;
=pod

=encoding utf8

=head1 NAME

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut

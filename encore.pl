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
    use IPC::Run qw(run start pump finish);
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
use IPC::SysV qw(IPC_PRIVATE S_IRUSR S_IWUSR IPC_CREAT);
use IPC::Semaphore;

# semaphores
our %sem;

#$SIG{'TERM'} = sub {
#    exit 1;
#};

sub subst($env, @xs){
    @xs = grep defined, @xs;
    return map {
        s/\$(\S+)/$env->{$1}/; $_
    } @xs;
}
sub proc_eval($proc, $args, @program){
    my @args = grep defined, @$args;
    my %env;
    my @bg_jobs;
    # a proc should be a list of commands
    for(@program){
        if(m/^\@arg\s+(\d+)\s+\$(\S+)$/){
            $env{$2} = $args[$1];
            next;
        }
        s/\$(\S+)/$env{$1}/;
        say STDERR "[$proc] " . join ' ', split ' ';
        if(m/^\@wait\s+(\S+)$/){
            say "$proc: FOO";
            $sem{$1}->op(0, -1, 0);
            say "$proc: BAR";
        }
        elsif(m/^\@done$/){
            $sem{$proc}->op(0, 1, 0);
        }
        elsif(m/^\@&/){
            my @cmd = split ' ';
            shift @cmd;
            my $in;
            my $out;
            my $harness = start \@cmd, \$in, \$out;
            if(m/^\@&&/){
                my $stdout;
                do{
                    $stdout = capture_stdout {
                        run ['xdotool', 'search', 'evince']
                    };
                    sleep(1);
                } while(!length $stdout);
            }
            push @bg_jobs, $harness;
        }
        else{
            my $stdout = capture_stdout {
                run [split ' '];
            };
            say "[$proc] stdout: $stdout";
        }
    }
    say STDERR "[$proc] waiting for bg";
    for(@bg_jobs){
        finish $_ or croak "Uh oh. $!";
    }
    say STDERR "[$proc] exiting";
    sleep 100;
}

$ENV{DISPLAY}=':0'; # TODO: hack for now
# read YAML program
my %program = %{YAML::XS::LoadFile $ARGV[0]};
# require 'main' top level key
my @main = @{$program{main}};
delete $program{main};
# main's script variables
my %env;
# main should be a sequence of commands, then a key-value describing the procs and their arguments
# NOTE: for now, we assume the sequence of commands are just "@arg n $var" builtins
for(@main){
    if(defined(reftype $_)){ # must be procs and args
        if(reftype $_ eq 'HASH'){
            say STDERR "starting main with %env:";
            say STDERR YAML::XS::Dump(\%env) . '...';
            my %exec = %$_;
            my %child_pids;
            for my $proc (keys %exec){
                $sem{$proc} = IPC::Semaphore->new(IPC_PRIVATE, 1, S_IRUSR | S_IWUSR | IPC_CREAT);
                $sem{$proc}->setval(0, 0);
            }
            for my $proc (keys %exec){
                my $pid = fork;
                if(defined $pid){
                    if($pid){ # parent
                        $child_pids{$proc} = $pid;
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
            for(map {$child_pids{$_}} keys %child_pids){
                waitpid $_, 0;
            }
        }
        else{
            croak "main should be a hash of procs";
        }
    }
    elsif(m/^\@arg\s+(\d+)\s+\$(\S+)$/){ # else @arg builtin
        say STDERR "$ARGV[1 + $1] -> \$$2";
        $env{$2} = $ARGV[1 + $1];
    }
    else{
        croak "main is malformed at line: $_";
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

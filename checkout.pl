#!/usr/bin/perl
use warnings;
use strict;
use Cwd qw(getcwd);
use POSIX qw(WEXITSTATUS);
use Config;

open( RVV, '<', 'RepoVivadoVersion' );
my $VIVADO_VERSION = <RVV>;
chomp $VIVADO_VERSION;
close(RVV);
unless ($VIVADO_VERSION) {
    printf
      "Unable to detect the Vivado version in use in this repository.\n";
    exit(1);
}

#Find the Vivado executable, per system we are on
#Need to manually search PATH as cygwin doesn't find it always after the Vivado
#setup script is run (adds path components in Windows form, but doesn't run
#if translated to cygwin form.)
my $VIVADO = undef;
if ( $Config{osname} =~ /cygwin/ ) {
    $VIVADO = cygwin_find_in_path('vivado');
    $VIVADO = `cygpath --windows $VIVADO`;
    chomp $VIVADO;
}
elsif ( $Config{osname} =~ /MSWin/ ) {
    $VIVADO = windows_find_in_path('vivado');
}
else {
    my $viv_temp = `which vivado`;
    chomp $viv_temp;
    $VIVADO = $viv_temp if $? == 0;
}

if ( $VIVADO !~ m!\Q$VIVADO_VERSION\E! ) {
    printf
      "You are not running Vivado $VIVADO_VERSION or have not sourced the environment initialization scripts.  Aborting.\n";
    exit(1);
}

my %MESSAGES;

printf "~~~ Destroying backup workspace! ~~~\n";
system( 'rm', '-rf', 'workspace.bak' );
printf "\n";
printf "~~~ Backing up and replacing current workspace\n";
if ( -e 'workspace' && !rename( 'workspace', 'workspace.bak' ) ) {
    printf "~~~ Failed to rename workspace to workspace.bak.  Aborting.\n";
    exit(2);
}
if ( !mkdir('workspace') ) {
    printf "~~~ Failed to create workspace.  Aborting.\n";
    exit(2);
}

if ( -e 'ip_repo_sources' ) {
    printf "\n";
    printf "~" x 80 . "\n";
    printf "~~~ COPYING IP_REPO\n";
    printf "~~~\n";
    system( 'rsync',            '-rhtci', '--del',
            'ip_repo_sources/', 'workspace/ip_repo/' );
    printf "~~~\n";
    printf "\n";
}

open( PROJECTLIST, '<', 'projects.list' );
while ( my $ProjectCanonicalName = <PROJECTLIST> ) {
    chomp $ProjectCanonicalName;
    my $SourcesDir = sprintf( "sources/%s", $ProjectCanonicalName );
    my $ProjectDir
      = sprintf( "%s/workspace/%s", getcwd(), $ProjectCanonicalName );
    $MESSAGES{$ProjectCanonicalName} = [];

    my @cmd;    # For running VIVADO

    printf "~" x 80 . "\n";
    printf "~~~ Processing Project: %s\n", $ProjectCanonicalName;
    printf "~~~\n";
    printf "~~~ Sourcing Project TCL in Vivado\n";
    @cmd = ( $VIVADO, '-mode', 'batch', '-nojournal', '-nolog', '-source',
             sprintf( "sources/%s.tcl", $ProjectCanonicalName )
           );
    if ( $Config{osname} =~ /cygwin/ ) {

        # Cygwin has problems starting vivado on another drive for some reason
        # Force to run through CMD, which doesn't seem to hcave the problem
        unshift @cmd, "cmd", '/c';
    }
    system(@cmd);

    if ( WEXITSTATUS($?) ) {
        push @{ $MESSAGES{$ProjectCanonicalName} },
          { Severity => 'CRITICAL ERROR',
            Message =>
              sprintf(
                "Vivado exited with an unexpected status code after project regeneration: %s.  Aborting.  The project has NOT necessarily been safely or fully created!",
                WEXITSTATUS($?) )
          };
    }
    else {
        printf "~~~ Running any project-specific initialization scripts\n";
        my @InitScripts;
        push @InitScripts,
          sprintf( "initscripts/%s.pl", $ProjectCanonicalName );
        push @InitScripts,
          sprintf( "initscripts/%s.sh", $ProjectCanonicalName );
        push @InitScripts,
          sprintf( "initscripts/%s.py", $ProjectCanonicalName );
        for my $InitScript (@InitScripts) {
            if ( -x $InitScript ) {
                printf "~~~ Running %s\n", $InitScript;
                system( $InitScript,
                        sprintf( "%s/%s.xpr",
                                 $ProjectDir, $ProjectCanonicalName )
                      );
                if ( WEXITSTATUS($?) ) {
                    push @{ $MESSAGES{$ProjectCanonicalName} },
                      { Severity => 'WARNING',
                        Message =>
                          sprintf(
                            "Project initialization script %s exited with nonzero status: %s!",
                            $InitScript, WEXITSTATUS($?)
                          )
                      };
                }
            } ## end if ( -x $InitScript )
        } ## end for my $InitScript (@InitScripts)
        my $InitScript
          = sprintf( "initscripts/%s.tcl", $ProjectCanonicalName );
        if ( -f $InitScript ) {
            printf "~~~ Running %s\n", $InitScript;
            @cmd = (
                   $VIVADO, '-mode', 'batch', '-nojournal', '-nolog',
                   '-source', $InitScript,
                   sprintf( "%s/%s.xpr", $ProjectDir, $ProjectCanonicalName )
            );
            if ( $Config{osname} =~ /cygwin/ ) {

                # Cygwin has problems starting vivado on another drive for some reason
                # Force to run through CMD, which doesn't seem to hcave the problem
                unshift @cmd, "cmd", '/c';
            }
            system(@cmd);
            if ( WEXITSTATUS($?) ) {
                push @{ $MESSAGES{$ProjectCanonicalName} },
                  { Severity => 'WARNING',
                    Message  => sprintf(
                        "Project initialization script %s exited with nonzero status: %s!",
                        $InitScript, WEXITSTATUS($?)
                    )
                  };
            }
        } ## end if ( -f $InitScript )
    } ## end else [ if ( WEXITSTATUS($?) )]

    printf "~~~\n";
    printf "~~~ Finished processing project %s\n", $ProjectCanonicalName;

    printf "\n";
    printf "\n";
    if ( @{ $MESSAGES{$ProjectCanonicalName} } ) {
        printf "~" x 80 . "\n";
        printf "~~~ MESSAGES FOR PROJECT %s\n", $ProjectCanonicalName;
        printf "~~~\n";
        for my $Message ( @{ $MESSAGES{$ProjectCanonicalName} } ) {
            printf "~~~ %s: %s\n", $Message->{Severity}, $Message->{Message};
        }
        printf "~~~\n";
    }
} ## end while ( my $ProjectCanonicalName...)

my %MessageTotals;
for my $ProjectCanonicalName ( keys %MESSAGES ) {
    if ( @{ $MESSAGES{$ProjectCanonicalName} } ) {
        printf "\n\n\n" unless (%MessageTotals);
        printf "~" x 80 . "\n";
        printf "~~~ MESSAGES FOR PROJECT %s\n", $ProjectCanonicalName;
        printf "~~~\n";
        for my $Message ( @{ $MESSAGES{$ProjectCanonicalName} } ) {
            printf "~~~ %s: %s\n", $Message->{Severity}, $Message->{Message};
            $MessageTotals{ $Message->{Severity} } = 0
              unless exists( $MessageTotals{ $Message->{Severity} } );
            $MessageTotals{ $Message->{Severity} }++;
        }
        printf "~~~\n";
    } ## end if ( @{ $MESSAGES{$ProjectCanonicalName...}})
} ## end for my $ProjectCanonicalName...
if ( grep { $_ } values %MessageTotals ) {
    printf "~" x 80 . "\n";
    for my $MessageType ( sort keys %MessageTotals ) {
        printf "~~~ %u %s messages\n", $MessageTotals{$MessageType},
          $MessageType;
    }
    printf
      "~~~ Please review them carefully and make sure none are dangerous before proceeding.\n";
}
else {
    printf
      "~~~ No issues encountered.  Projects generated and ready to use.\n";
}

sub cygwin_find_in_path {
    my ($executable) = @_;

    my @split_paths = split( /(?<!:[A-Za-z]):/, $ENV{PATH} );

    #If the first directory in the path is in windows form, it will be incorrectly split
    if (    ( $split_paths[0] =~ /^[A-Za-z]$/ )
         && ( $split_paths[1] =~ /^\\/ ) )
    {
        my $temp0 = shift @split_paths;
        my $temp1 = shift @split_paths;

        unshift @split_paths, ( $temp0 . ":" . $temp1 );
    }

    my @fix_paths
      = map { my $n = `cygpath --unix "$_"`; chomp $n; $n } @split_paths;

    foreach my $p (@fix_paths) {
        my $tp = "$p/$executable";
        if ( -X $tp ) {
            return $tp;
            last;
        }
    }

    return undef;
} ## end sub cygwin_find_in_path

sub windows_find_in_path {
    my ($executable) = @_;

    my @endings = ( "exe", "bat", "com" );

    my $need_endings = 1;

    for my $ending (@endings) {
        if ( $executable =~ /\.$ending$/i ) {
            $need_endings = 0;
        }
    }

    my @split_paths = split( /;/, $ENV{PATH} );

    foreach my $p (@split_paths) {
        my $tp;

        if ( !$need_endings ) {
            $tp = "$p\\$executable";
            if ( -X $tp ) {
                return $tp;
                last;
            }
        }
        else {
            foreach my $ending (@endings) {
                $tp = "$p\\$executable.$ending";
                if ( -X $tp ) {
                    return $tp;
                    last;
                }
            }
        }
    } ## end foreach my $p (@split_paths)

    return undef;
} ## end sub windows_find_in_path

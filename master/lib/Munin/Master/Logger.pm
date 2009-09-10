package Munin::Master::Logger;

# $Id: $

use base qw(Exporter);

use strict;
use warnings;

use English qw(-no_match_vars);
use File::Basename qw(basename);
use Log::Log4perl qw(:easy);

our @EXPORT = qw(logger_open logger_debug logger_level logger);

#
# Switching to Log4perl over time.  Management and compatability goes here.
#

# Early open of the log.  Warning and more urgent messages will go to
# screen.

Log::Log4perl->easy_init( $WARN );

my $logdir = undef;
my $logopened = 0;
my $me = basename($PROGRAM_NAME);


sub logger_open {
    # This is called when we have a directory and file name to log in.

    my $dirname = shift;
    $logdir=$dirname;

    if (!defined($dirname)) {
	confess("In logger_open, directory for log files undefined");
    }

    if (!$logopened) {
	# I'm a bit uncertain about the :utf8 bit.
	Log::Log4perl->easy_init( { level    => $INFO,
				    file     => ":utf8>>$dirname/$me.log" } );
	# warn "Logging to $dirname/$me.log";
	$logopened = 1;
    }

    get_logger('')->info("Opened log file!");
}

sub logger_debug {
    # Adjust log level to DEBUG if user gave --debug option
    my $logger = get_logger('');

    WARN "Setting log level to DEBUG\n";

    if (defined($logdir)) {
	Log::Log4perl->easy_init( { level    => $DEBUG,
				    file     => ":utf8>>$logdir/$me.log" },
				  { level    => $DEBUG,
				    file     => "STDERR" } );
    } else {
	# If we do not have a log file name to log to just send
	# everything to STDERR
	Log::Log4perl->easy_init( { level    => $DEBUG,
				    file     => "STDERR" } );
    }
    # And do not open the loggers again now.
    $logopened=1;
}

sub logger_level {
    my ($loglevel) = @_;

    my $logger = get_logger('');

    $loglevel = lc $loglevel;
    my %level_map = (
        trace => $TRACE,
        debug => $DEBUG,
        info  => $INFO,
        warn  => $WARN,
        error => $ERROR,
        fatal => $FATAL,
    );

    unless ($level_map{$loglevel}) {
        ERROR "Unknown log level: '$loglevel'\n";
        return;
    }

    $logger->level($level_map{$loglevel});

    INFO "Setting log level to $loglevel\n";
}

sub logger {
  my ($comment) = @_;

  INFO @_;
}

1;

__END__

=head1 NAME

FIX

=head1 SYNOPSIS

=head1 SUBROUTINES

=over

=item B<logger_open>

=item B<logger>

=item B<logger_level>

=item B<logger_debug>

=back
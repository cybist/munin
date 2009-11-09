package Munin::Master::Update;

# $Id$

use warnings;
use strict;

use English qw(-no_match_vars);
use Carp;

use Time::HiRes;
use Log::Log4perl qw( :easy );

use Munin::Common::Defaults;
use Munin::Master::Config;
use Munin::Master::Logger;
use Munin::Master::UpdateWorker;
use Munin::Master::ProcessManager;
use Munin::Master::Utils;

my $config = Munin::Master::Config->instance()->{config};

sub new {
    my ($class) = @_;

    # This steals the groups from the master instance of the config.
    my $gah = $config->get_groups_and_hosts();

    my $self = bless {
        STATS               => undef,
        old_service_configs => {},
        old_version         => undef,
        service_configs     => {},
        workers             => [],
        failed_workers      => [],
        group_repository    => Munin::Master::GroupRepository->new($gah),
        config_dump_file    => "$config->{dbdir}/datafile",
    }, $class;
}


sub run {
    my ($self) = @_;
    
    $self->_create_rundir_if_missing();

    $self->_do_with_lock_and_timing(sub {
        INFO "[INFO] Starting munin-update";

        $self->{old_service_configs} = $self->_read_old_service_configs();

        $self->{workers} = $self->_create_workers();
        $self->_run_workers();

	# I wonder if the following should really be done with timing. - janl
        $self->_write_new_service_configs_locked();
    });
}


sub _read_old_service_configs {

    # Read the datafile containing old configurations.  This should
    # not fail in case of problems with the file.  In such a case the
    # file should simply be ingored and a new one written.  Lets hope
    # it does not repeat itself then.

    my ($self) = @_;

    # Get old service configuration from the config instance since the
    # syntaxes are identical.
    my $oldconfig = Munin::Master::Config->instance()->{oldconfig};

    my $datafile = $oldconfig->{config_file} = $config->{dbdir}.'/datafile';

    my $file;
    
    if (-e $datafile ) {
	if (! open( $file, '<', $datafile)) {
	    WARN "[Warning] Cannot open datafile $datafile";
	    return {};
	}
	eval {
	    $oldconfig->parse_config($file);
	};
	if ($EVAL_ERROR) {
	    WARN "[Warning] Could not parse datafile $datafile: $EVAL_ERROR";
	}
    }
    return $oldconfig;
}


sub _create_rundir_if_missing {
    my ($self) = @_;

    unless (-d $config->{rundir}) {
	mkdir $config->{rundir}, oct(700)
            or croak "Failed to create rundir (".$config->{rundir}."): $!";
        
    }
}


sub _create_workers {
    my ($self) = @_;

    # FIX log skipped and queued workers:
    # logger("Skipping '$name' (update disabled by config)");
    # logger("Queuing '$name' for update.");

    my @hosts = $self->{group_repository}->get_all_hosts();

    if (%{$config->{limit_hosts}}) {
        @hosts = grep { $config->{limit_hosts}{$_->{host_name}} } @hosts
    }

    @hosts = grep { $_->{update} } @hosts;

    return [ map { Munin::Master::UpdateWorker->new($_) } @hosts ];
}


sub _do_with_lock_and_timing {
    my ($self, $block) = @_;

    my $lock = "$config->{rundir}/munin-update.lock";
    munin_runlock($lock);

    my $update_time = Time::HiRes::time;
    if (!open ($self->{STATS}, '>', "$config->{dbdir}/munin-update.stats.tmp")) {
        WARN "[WARNING] Could not open STATS to $config->{dbdir}/munin-update.stats.tmp: $!";
        # Use /dev/null instead - if the admin won't fix he won't care
        open($self->{STATS}, '>', "/dev/null") or LOGCROAK "[FATAL] Could not open STATS to /dev/null (fallback for not being able to open $config->{dbdir}/munin-update.stats.tmp): $!";
    }

    my $retval = $block->();

    $update_time = sprintf("%.2f", (Time::HiRes::time - $update_time));
    print { $self->{STATS} } "UT|$update_time\n";
    close ($self->{STATS});
    $self->{STATS} = undef;
    rename ("$config->{dbdir}/munin-update.stats.tmp", "$config->{dbdir}/munin-update.stats");
    INFO "[INFO] Munin-update finished ($update_time sec)";

    munin_removelock($lock);

    return $retval;
}


sub _run_workers {
    my ($self) = @_;

    if ($config->{fork}) {
        my $pm = Munin::Master::ProcessManager
            ->new($self->_create_self_aware_worker_result_handler(),
                  $self->_create_self_aware_worker_exception_handler());
        $pm->add_workers(@{$self->{workers}});
        $pm->start_work();
    }
    else {
        for my $worker (@{$self->{workers}}) {
            my $res = $worker->do_work();
            $self->_handle_worker_result([$worker->{ID}, $res]);
        }
    }
}


sub _create_self_aware_worker_result_handler {
    my ($self) = @_;

    return sub { $self->_handle_worker_result(@_); };
}


sub _handle_worker_result {
    my ($self, $res) = @_;

    my ($worker_id, $time_used, $service_configs) 
        = ($res->[0], $res->[1]{time_used}, $res->[1]{service_configs});

    if (! defined $self->{STATS} ) {
	# This is may only be the case when we get connection refused
	ERROR "[FIX?] Did not collect any stats for $worker_id";
    } else {
	printf { $self->{STATS} } "UD|%s|%.2f\n", $worker_id, $time_used;
    }

    $self->{service_configs}{$worker_id} = $service_configs;
}


sub _create_self_aware_worker_exception_handler {
    my ($self) = @_;

    return sub {
        my ($worker_id, $reason) = @_;
	WARN "[WARNING] Failed worker $worker_id";
        push @{$self->{failed_workers}}, $worker_id;
    };
}


# FIX merge with UpdateWorker::_get_rrd_file_name
# FIX seems like dead code?  Or only used in ensure_?
sub _get_rrd_file_name {
    my ($self, $host, $service, $ds_name, $ds_type) = @_;
    
    my $type_id = lc(substr(($ds_type), 0, 1));
    my ($g, $h) = split /;/, $host;
    # // ... perl mode
    my $file = sprintf("%s-%s-%s-%s.rrd",
                       $h,
                       $service,
                       $ds_name,
                       $type_id);

    # Not really a danger (we're not doing this stuff via the shell),
    # so more to avoid confusion with silly filenames.
    ($g, $file) = map { 
        my $p = $_;
        $p =~ tr/\//_/; 
        $p =~ s/^\./_/g;
        $p;
    } ($g, $file);
	
    my $rrd_file = File::Spec->catfile($config->{dbdir}, 
                                       $g,
                                       $file);
    croak "RRD file '$rrd_file' not found" unless -e $rrd_file;

    return $rrd_file;
}


sub _write_new_service_configs_locked {
    my ($self) = @_;

    my $lock_file = "$config->{rundir}/munin-datafile.lock";
    munin_runlock($lock_file);

    open my $dump, '>', $self->{config_dump_file}
        or croak "Fatal error: Could not open '$self->{config_dump_file}' for writing: $!";

    $self->_write_new_service_configs($dump);

    close $dump
        or croak "Fatal error: Could not close '$self->{config_dump_file}': $!";

    munin_removelock($lock_file);
}


sub _write_new_service_configs {
    my ($self, $io) = @_;

    $self->_copy_old_service_config_for_failed_workers();

    print $io "version $Munin::Common::Defaults::MUNIN_VERSION\n";
    for my $host (keys %{$self->{service_configs}}) {
        for my $service (keys %{$self->{service_configs}{$host}{data_source}}) {
            for my $attr (@{$self->{service_configs}{$host}{global}{$service}}) {
                print $io "$host:$service.$attr->[0] $attr->[1]\n";
            }
            for my $data_source (keys %{$self->{service_configs}{$host}{data_source}{$service}}) {
                for my $attr (keys %{$self->{service_configs}{$host}{data_source}{$service}{$data_source}}) {
                    print $io "$host:$service.$data_source.$attr $self->{service_configs}{$host}{data_source}{$service}{$data_source}{$attr}\n";
                }
            }
        }
    }
}


sub _copy_old_service_config_for_failed_workers {
    my ($self) = @_;

    for my $worker (@{$self->{failed_workers}}) {
	next if !defined($worker);  # The empty set contains "undef" it seems
        $self->{service_configs}{$worker} = $self->{old_service_configs}{$worker};
    }
}


1;


__END__

=head1 NAME

Munin::Master::Update - Contacts Munin Nodes, gathers data from their
service data sources, and stores this information in RRD files.

=head1 SYNOPSIS

 my $update = Munin::Master::Update->new();
 $update->run();

=head1 METHODS

=over

=item B<new>

 my $update = Munin::Master::Update->new();

Constructor.

=item B<run>

 $update->run();

This is where all the work gets done.

=back


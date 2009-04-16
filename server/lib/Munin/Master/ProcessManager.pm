package Munin::Master::ProcessManager;

use warnings;
use strict;

use Carp;
use English qw(-no_match_vars);
use IO::Socket;
use Munin::Common::Timeout;
use Munin::Master::Logger;
use POSIX qw(:sys_wait_h);
use Storable qw(nstore_fd fd_retrieve);


my $E_DIED      = 18;
my $E_TIMED_OUT = 19;


sub new {
    my ($class, $result_callback, $error_callback) = @_;

    croak "Argument exception: result_callback"
        unless ref $result_callback eq 'CODE';

    $error_callback ||= sub { warn "Worker failed: @_" };

    my $self = {
        max_concurrent  => 2,
        socket_file     => '/tmp/MuninMasterProcessManager.sock',
        result_callback => $result_callback,
        error_callback  => $error_callback,

        worker_timeout  => 1,
        timeout         => 10,
        accept_timeout  => 1,

        active_workers  => {},
        result_queue    => {},
        pid2worker      => {},
    };
    
    return bless $self, $class;
}


sub add_workers {
    my ($self, @workers) = @_;

    for my $worker (@workers) {
        croak "Argument exception: \@workers"
            unless $worker->isa('Munin::Master::Worker');
    }

    $self->{workers} = \@workers;
}


sub start_work {
    my ($self) = @_;
    
    $self->{iterator_index} = 0;
    
    my $sock = $self->_prepare_unix_socket();

    for my $worker (@{$self->{workers}}) {
        my $pid = fork;
        if (!defined $pid) {
            croak "$!";
        }
        elsif ($pid) {
            $self->{active_workers}{$pid} = $worker;
            $self->{result_queue}{$worker->{ID}} = $worker;
        }
        else {
            $0 .= " [$worker]";
            eval {
                exit $self->_do_work($worker);
            };
            if ($EVAL_ERROR) {
                logger("[ERROR] $worker died with '$EVAL_ERROR'");
                exit $E_DIED;
            }
        } 
    }

    do_with_timeout($self->{timeout}, sub {
        $self->_collect_results($sock);
    }) or croak "Work timed out before all workers finished";
    $self->{workers} = [];
    logger("Work done");
}


sub _collect_results {
    my ($self, $sock) = @_;

    while (%{$self->{result_queue}}) {
        $self->_vet_finished_workers();

        my $worker_sock;
        my $timed_out = !do_with_timeout($self->{accept_timeout}, sub {
            accept $worker_sock, $sock;
        });
        next if $timed_out;
        next unless fileno $worker_sock;

        my $res = fd_retrieve($worker_sock);
        my ($worker_id, $real_res) = @$res;

        delete $self->{result_queue}{$worker_id};

        $self->{result_callback}($res) if defined $real_res;
    }
}


sub _vet_finished_workers {
    my ($self) = @_;

    while ((my $worker_pid = waitpid(-1, WNOHANG)) > 0) {
        if ($CHILD_ERROR) {
            $self->_handle_worker_error($worker_pid);
        }
        delete $self->{active_workers}{$worker_pid};
    }
}


sub _handle_worker_error {
    my ($self, $worker_pid) = @_;
    
    my %code2msg = (
        $E_TIMED_OUT => 'Timed out',
        $E_DIED      => 'Died',
    );
    my $worker_id = $self->{active_workers}{$worker_pid}{ID};
    my $exit_code = $CHILD_ERROR >> 8;
    $self->{error_callback}($self->{worker_pids}{$worker_pid},
                            $code2msg{$exit_code} || $exit_code);
    delete $self->{result_queue}{$worker_id};

}



sub _prepare_unix_socket {
    my ($self) = @_;

    unlink $self->{socket_file}
        or $! ne 'No such file or directory' && croak "unlink failed: $!";
    socket my $sock, PF_UNIX, SOCK_STREAM, 0
        or croak "socket failed: $!";
    bind $sock, sockaddr_un($self->{socket_file})
        or croak "bind failed: $!";
    chmod oct(700), $self->{socket_file}
        or croak "chomd failed: $!";
    listen $sock, SOMAXCONN
        or croak "listen failed: $!";
    
    return $sock;
}


sub _do_work {
    my ($self, $worker) = @_;

    my $retval = 0;

    my $res;
    my $timed_out = !do_with_timeout($self->{worker_timeout}, sub {
        $res = $worker->do_work();
    });
    if ($timed_out) {
        logger("[ERROR] $worker timed out");
        $res = undef;
        $retval = $E_TIMED_OUT;
    }
    
    my $sock;
    unless (socket $sock, PF_UNIX, SOCK_STREAM, 0) {
        logger("[ERROR] Unable to create socket: $!");
        return $E_DIED;
    }
    unless (connect $sock, sockaddr_un($self->{socket_file})) {
        logger("[ERROR] Unable to connect to socket: $!");
        return $E_DIED;
    }
    
    nstore_fd([ $worker->{ID},  $res], $sock);

    close $sock;
    return $retval;
}


1;


__END__

=head1 NAME

FIX

=head1 SYNOPSIS

FIX

=head1 METHODS

FIX


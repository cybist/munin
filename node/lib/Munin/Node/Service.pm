package Munin::Node::Service;

# $Id$

use warnings;
use strict;

use English qw(-no_match_vars);
use Carp;

use Munin::Node::Config;
use Munin::Node::OS;
use Munin::Node::Logger;

use Munin::Common::Defaults;

my $config = Munin::Node::Config->instance();


sub is_a_runnable_service {
    my ($class, $file, $dir) = @_;
    
    $dir ||= $config->{servicedir};

    my $path = "$dir/$file";

    return unless -f $path && -x _;

    # FIX isn't it enough to check that the file is executable and not
    # in 'ignores'? Can hidden files and config files be
    # unintentionally executable? What does config files do in the
    # service directory? Shouldn't we complain if there is junk in the
    # service directory?
    return if $file =~ m/^\./;               # Hidden files
    return if $file =~ m/\.conf$/;            # Config files

    return if $file !~ m/^([-\w.:]+)$/;      # Skip if any weird chars

    $file = $1;                              # Not tainted anymore.

    foreach my $regex (@{$config->{ignores}}) {
        return if $file =~ /$regex/;
    }
    
    return 1;
}


sub export_service_environment {
    my ($class, $service) = @_;
    print STDERR "# Setting up environment\n" if $config->{DEBUG};

    my $env = $config->{sconf}{$service}{env};

    return unless defined $env;
    while (my ($k, $v) = each %$env) {
        print STDERR "# Environment $k = $v\n" if $config->{DEBUG};
        $ENV{$k} = $v;
    }
}


sub change_real_and_effective_user_and_group
{
    my ($class, $service) = @_;

    my $root_uid = 0;
    my $root_gid = 0;

    if ($REAL_USER_ID == $root_uid) {
        # Need to test for defined here since a user might be
        # specified with UID = 0
        my $uid = defined $config->{sconf}{$service}{user} 
                    ? $config->{sconf}{$service}{user}
                    : $config->{defuser};
        
        # Resolve unresolved UID now - as it is may not have been resolved
        # when the config was read.
        my $u = Munin::Node::OS->get_uid($uid);
        croak "User '$uid' is nonexistent." unless defined $u;
        my $dg  = $config->{defgroup};

        my $g = '';
        my $gid;

        if ( defined($gid = $config->{sconf}{$service}{group}) ) {
            $g = Munin::Node::OS->get_gid($gid);
            croak "Group '$gid' is nonexistent." unless $g ne '';
        }

        # Specify the default group twice: once for setegid(2), and once
        # for setgroups(2).  See perlvar for the gory details.
        my $gs = "$dg $dg $g";

	print STDERR "# Set rgid/ruid/egid/euid to $dg/$u/$gs/$u\n"
	    if $config->{DEBUG};

        eval {
            if ($Munin::Common::Defaults::MUNIN_HASSETR) {
                Munin::Node::OS->set_real_group_id($dg) 
                      unless $dg == $root_gid;
                Munin::Node::OS->set_real_user_id($u)
                      unless $u == $root_uid;
            }

            Munin::Node::OS->set_effective_group_id($gs) 
                  unless $dg == $root_gid;
            Munin::Node::OS->set_effective_user_id($u)
                  unless $u == $root_uid;
        };

        if ($EVAL_ERROR) {
            logger("Plugin \"$service\" Can't drop privileges: $EVAL_ERROR. "
                       . "Bailing out.\n");
            exit 1;
        }
    }
    else {
        if (defined $config->{sconf}{$service}{user}
         or defined $config->{sconf}{$service}{group})
        {
            print "# Warning: Root privileges are required to change user/group.  "
                . "The plugin may not behave as expected.\n";
        }
    }
}


sub exec_service {
    my ($class, $dir, $service, $arg) = @_;

    $arg ||= '';

    $class->change_real_and_effective_user_and_group($service);

    unless (Munin::Node::OS->check_perms("$dir/$service")) {
        logger ("Error: unsafe permissions on $service. Bailing out.");
        exit 2;
    }

    $class->export_service_environment($service);

    my @command = _service_command($dir, $service, $arg);
    print STDERR "# About to run '", join (' ', @command), "'\n" if $config->{DEBUG};
    exec @command;
}


sub _service_command
{
    my ($dir, $service, $argument) = @_;

    my @run = ();
    my $sconf = $config->{sconf};

    if ($sconf->{$service}{command}) {
        for my $t (@{ $sconf->{$service}{command} }) {
            if ($t eq '%c') {
                push @run, ("$dir/$service", $argument);
            } else {
                push @run, ($t);
            }
        }
    }
    else {
        @run = ("$dir/$service", $argument);
    }

    return @run;
}


sub fork_service
{
    my ($class, $dir, $service, $arg) = @_;

    my $timeout = $config->{sconf}{$service}{timeout} 
                  || $config->{timeout};

    my $run_service = sub {
        $class->exec_service($dir, $service, $arg);
        # shouldn't be reached
        print STDERR "# ERROR: Failed to exec.\n";
        exit 42;
    };

    return Munin::Node::OS->run_as_child($timeout, $run_service);
}


1;

__END__


=head1 NAME

Munin::Node::Service - Methods related to handling of Munin services


=head1 SYNOPSIS


 my $bool = Munin::Node::Service->is_a_runnable_service($file_name);
 $result = Munin::Node::Service->fork_service($file_name)
    if $bool;

=head1 METHODS

=over

=item B<is_a_runnable_service>

 my $bool = Munin::Node::Service->is_a_runnable_service($file_name, $dir);

Runs miscellaneous tests on $file_name in directory $dir. These tests are 
intended to verify that $file_name is a runnable service.

If not specified, $dir defaults to $config->{servicedir}

=item B<export_service_environment>

 Munin::Node::Service->export_service_enviromnent($service);

Exports all the environment variables specific to service $service.

=item B<change_real_and_effective_user_and_group>

 Munin::Node::Service->change_real_and_effective_user_and_group($service);

Changes the current process' effective group and user IDs to those specified
in the configuration, or the default user or group otherwise.  Also changes 
the real group and user IDs if the operating system supports it.

On failure, causes the process to exit.

=item B<exec_service>

 Munin::Node::Service->exec_service($directory, $service, [$argument]);

Replaces the current process with an instance of service $service in $directory,
running with the correct environment and privileges.

This function never returns.

=item B<fork_service>

 $result = Munin::Node::Service->fork_service($directory, $service, [$argument]);

Identical to exec_service(), except it forks off a child to run the service.
If the service takes longer than its configured timeout, it will be terminated.

Returns a hash reference containing (among other things) the service's output
and exit value.  (See documentation for run_as_child() in
L<Munin::Node::Service> for a comprehensive description.)

=back

=cut

# vim:syntax=perl : ts=4 : expandtab

#!/bin/env perl
use strict;
use warnings;
use JSON;
#use Data::Dumper;
use IPC::Open2;
use IO::Select;
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC );
use Getopt::Long qw(:config no_ignore_case);
use Pod::Usage;

my $help;
my $man;
my $confFile;
my $daemon;


GetOptions (
    'man|m' => \$man,
    'help|h' => \$help,

    'file|f=s' => \$confFile,
    'table|t' => sub{gen_table(), exit(0)},
    'json|j' => sub{gen_json(), exit(0)},
    'daemon|d' => \$daemon,

) or pod2usage(2);

usage(-exitval => 0, -verbose => 98) if $help;
usage(-exitval => 0, -verbose => 2) if $man;

usage(-exitval => 1, -verbose => 1, -message => "Need at least one option.\n") if !$confFile and !$daemon;
usage(-exitval => 1, -verbose => 1, -message => "Incorrect daemon invocation, config file not specified.\n",
    -sections => ['SYNOPSYS', 'OPTIONS', 'EXAMPLES/DAEMON']) if !$confFile and $daemon;

sub usage
{
    my %args = @_;
    my $verbose = 0;
    my @format;

    if(defined $args{-sections}) {
	@format = @{$args{-sections}};
	delete $args{-sections};
    }
    if(defined $args{-verbose}) {
	$verbose = $args{-verbose};
	if($args{-verbose} == 98) {
	    # --help
	    $ENV{PERLDOC_PAGER} = 'cat'; # == pod2usage(@_, -noperldoc => 1);
	    if (scalar @format == 0) {
		@format = ('SYNOPSYS', 'OPTIONS', 'SHORT EXAMPLES');
	    }
	}
	delete $args{-verbose};
    }
    if (scalar @format > 0) {
	$verbose = 99;
    }
    pod2usage(%args, -verbose => $verbose, -sections => [@format]);
}



run($confFile, $daemon);
exit(0);

# ############################################################################ #
# ############################################################################ #
# ############################################################################ #

sub run
{
    my ($confFile, $daemon) = @_;

    if (not applyConf($confFile)) {
	# the first launch can fail if the loopback devices need to be created
	applyConf($confFile);
    }

    if ($daemon) {
	my $s = IO::Select->new();
	my $pid = open2(my $chld_out, my $chld_in, 'LANG=C pactl subscribe');
	$s->add($chld_out);

	my $needUpdate = 0;

	while (1) {
	    if ( $s->can_read(0) ) {
		my $line = <$chld_out> ;
		if (not $line =~ "on client") {
		    print "-----------------> $line\n";
		    $needUpdate++;
		}
	    } else {
		if ( $needUpdate > 0) {
		    my $t1 = clock_gettime(CLOCK_MONOTONIC);
		    applyConf($confFile);
		    my $t2 = clock_gettime(CLOCK_MONOTONIC);
		    printf("Conf applied in %f second.\n", $t2-$t1);
		    $needUpdate = 0;
		} else {
		    Time::HiRes::usleep(500000);# 500ms
		}
	    }
	}
	waitpid( $pid, 0 );
    }
}

# ############################################################################ #

sub gen_json
{
    my %curConfig;
    readCurConf(\%curConfig);
    print to_json(\%curConfig, {utf8 => 1, pretty => 1});

}

# ############################################################################ #

sub gen_table
{
    open(my $fh, '-|', 'pactl -f json list 2>/dev/null') or die $!;
    my $data = decode_json(<$fh>);
    close $fh;

    my %extract = ();
    simplifyJson(\%extract, $data);
    printAll(\%extract);
}

# ############################################################################ #

sub getid{
    (my $list, my $nodename) = @_;
    foreach my $idx (keys %$list) {
	if ($list->{$idx}->{'nodename'} eq $nodename) {
	    return $idx;
	}
    }
    return -1;
}

# ############################################################################ #

sub printAll {
    my ($data) = @_;

    my %kl = (); # length of each column
    foreach my $idx (keys %$data) {
	my $tmp = $data->{$idx};
	foreach my $attr (keys %$tmp) {
	    if (not defined $kl{$attr}) {
		$kl{$attr} = 0;
	    }
	    if (defined $tmp->{$attr}) {
		my $l = length($tmp->{$attr});
		if ($kl{$attr} < $l) {
		    $kl{$attr} = $l;
		}
	    }
	}
    }
    my $tot = 0;
    my $headline = '';
    my $c = '-';
    foreach my $key (keys %kl) {
	for (my $i=0; $i <= $kl{$key}; $i++) {
	    $headline .= $c;
	}
    }
    # add int length (burk)
    for (my $i=0; $i < 6 + 10 + 10 ; $i++) {
	$headline .= $c;
    }

    print("$headline\n");
    printf("| %$kl{key}s | %6s | %10s | %10s | %$kl{desc}s | %$kl{name}s | %$kl{nodename}s | %$kl{devdesc}s |\n",
	   "Category", "idx", "srcIdx", "SinkIdx", "Description", "Name", "Node.Name" , "Devdesc",
	);
    print("$headline\n");

    foreach my $idx (sort { $a <=> $b} keys %$data) {
	my $tmp = $data->{$idx};
	my $key = $tmp->{'key'};
	printf("| %$kl{key}s | %6d | %10d | %10d | %$kl{desc}s | %$kl{name}s | %$kl{nodename}s | %$kl{devdesc}s |\n",
	       $tmp->{'key'},
	       $idx,
	       $tmp->{'src'},
	       $tmp->{'dst'},
	       $tmp->{'desc'},
	       $tmp->{'name'},
	       $tmp->{'nodename'},
	       $tmp->{'devdesc'},
	    );
    }
    print("$headline\n");
}

# ############################################################################ #

sub readCurConf {
    my ($config) = @_;

    open(my $fh, '-|', 'pactl -f json list 2>/dev/null') or die $!;
    my $data = decode_json(<$fh>);
    close $fh;
    my %extract = ();

    simplifyJson(\%extract, $data);

    open($fh, '-|', 'pactl get-default-sink') or die $!;
    my $cur_def_sink = <$fh>;
    close $fh;
    chomp $cur_def_sink;

    open($fh, '-|', 'pactl get-default-source') or die $!;
    my $cur_def_source = <$fh>;
    close $fh;
    chomp $cur_def_source;

    my ($nodeo, $ntrasho) = getnode(\%extract, $cur_def_sink);
    my ($nodei, $ntrashi) = getnode(\%extract, $cur_def_source);
    $config->{'def_output'} = $nodeo;
    $config->{'def_input'} = $nodei;

    getloopback(\%extract, $config);
}

# ############################################################################ #

sub addnode{
   (my $list, my $cfg, my $n) = @_;
   my ($name, $node) = getnode($list, $n);
   if (defined $node) {
       if (not defined $cfg->{'nodes'}) {
	   $cfg->{'nodes'} = {};
       }
       $cfg->{'nodes'}->{$name} = $node;
   }
}

# ############################################################################ #

sub getnode{
    (my $list, my $n) = @_;
    # if $n is a string -> get the node by name
    # if $n is an integer -> get the node by id
    my $obj;
    my $id;
    if ($n =~ /^\d+$/) { # ~= is numeric
	if (not defined $list->{$n}) {
	    return;
	}
	$obj = $list->{$n};
	#$id = $n;
    } else {
	my $found = 0;
	foreach my $idx (keys %$list) {
	    my $tmp = $list->{$idx};
	    if (defined $tmp->{'nodename'} && $tmp->{'nodename'} eq $n) {
		$obj = $list->{$idx};
		#$id = $obj->{'idx'};
		$found = 1;
		last;
	    }
	}
	if ($found eq 0) {
	    return;
	}
    }
    my $desc = $obj->{'desc'};
    if (length($desc) == 0) {
	$desc = $obj->{'devdesc'};
    }
    my $ret = {
	    'desc' => $desc,
	    'devId' => $obj->{'idx'},
	    'base_volume' => $obj->{'base_volume'},
	   #'nodename' => $obj->{'nodename'},
	 };
    return ($obj->{'nodename'}, $ret);
}

# ############################################################################ #

sub getloopback{
    (my $list, my $cfg) = @_;

    my %loops;
    my $lname;
    foreach my $idx (keys %$list) {
	my $tmp = $list->{$idx};
	if (defined $tmp->{'devdesc'} && $tmp->{'devdesc'} =~ /loopback-/) {
	    $lname = $tmp->{'devdesc'};
	    if ($tmp->{'key'} eq 'source_outputs') {
		my ($nname, $onode) = getnode($list, $tmp->{'src'});
		$cfg->{'loopback'}{$tmp->{'devdesc'}}{'src'} = [ $nname ];
		$cfg->{'loopback'}{$tmp->{'devdesc'}}{'desc'} = $lname;
		$cfg->{'loopback'}{$tmp->{'devdesc'}}{'sourceId'} = $tmp->{'idx'};

		addnode($list, $cfg, $nname);

	    } elsif ($tmp->{'key'} eq 'sink_inputs') {
		my ($nname, $onode) = getnode($list, $tmp->{'dst'});
		$cfg->{'loopback'}{$tmp->{'devdesc'}}{'dst'} = [ $nname ];
		$cfg->{'loopback'}{$tmp->{'devdesc'}}{'desc'} = $lname;
		$cfg->{'loopback'}{$tmp->{'devdesc'}}{'sinkId'} = $tmp->{'idx'};
		#print Dumper $tmp;
		addnode($list, $cfg, $nname);
	    }
	}
    }

}

# ############################################################################ #

sub simplifyJson {
    my ($extract, $data) = @_;

    foreach my $key (keys %$data) {
	foreach my $i ( @{$data->{$key}} ) {
	    my $idx = -1;
	    if (defined $i->{'index'}) { $idx = $i->{'index'} };
	    my $name = '';
	    if (defined $i->{'name'}) { $name = $i->{'name'} };
	    my $desc = '';
	    if (defined $i->{'description'}) {
		$desc = $i->{'description'};
		if ($desc eq '(null)') {
		    $desc = '';
		}
	    };
	    my $source = -1;
	    if (defined $i->{'source'}) { $source = $i->{'source'} };
	    my $sink = -1;
	    if (defined $i->{'sink'}) { $sink = $i->{'sink'} };

	    my $base_volume;
	    if (defined $i->{'base_volume'} && defined $i->{'base_volume'}->{'value_percent'}) {
		$base_volume = $i->{'base_volume'}->{'value_percent'};
	    };

	    my $nodename = '';
	    #my $nodenick = 'node.nick';
	    my $devdesc = '';
	    my $nlink = '';
	    if (defined $i->{properties}) {
		if (defined $i->{properties}->{'node.name'}) {
		    $nodename = $i->{properties}->{'node.name'};
		    if ($nodename eq '(null)') {
			$nodename = '';
		    }
		}
		if (defined $i->{properties}->{'device.description'}) {
		    $devdesc = $i->{properties}->{'device.description'};
		}
		if (defined $i->{properties}->{'node.link-group'}) {
		    $nlink = $i->{properties}->{'node.link-group'};
		}
	    }
	    my %cur = ('key' => $key,
		       'idx' => $idx,
		       'name' => $name,
		       'desc' => $desc,
		       'src' => $source,
		       'dst' => $sink,
		       'base_volume' => $base_volume,
		       'devdesc' => $devdesc, # c'est ici qu'on a l'id du loopback :/
		       'nodename' => $nodename,
		);
	    $extract->{$idx} = \%cur;
	}
    }
}

# ############################################################################ #

sub applyConf {
    my ($fileName) = @_;
    my $rc = 1;

    open(my $fh, "<", $fileName) or die $! . " \"$fileName\"";
    my $str = '';
    while ( <$fh> ) {
	$str .= $_;
    }
    close $fh;
    my $fileConfig = decode_json($str);


    open($fh, '-|', 'pactl -f json list 2>/dev/null') or die $!;
    $str = <$fh>;
    close $fh;
    my $data = decode_json($str);
    my %curExtract = ();

    simplifyJson(\%curExtract, $data);

    my %curConfig;
    readCurConf(\%curConfig);

    # check definput
    if (defined $fileConfig->{'def_input'}) {
	if ($curConfig{'def_input'} ne $fileConfig->{'def_input'}) {
	    print("DBG: default input has changed\n");
	    my ($nName, $n) = getnode(\%curExtract, $fileConfig->{'def_input'});
	    print("DBG: pactl set-default-source $n->{'devId'}\n");
	    system("pactl set-default-source $n->{'devId'}\n");
	} else {
	    printf("def source OK: %s\n", $fileConfig->{'def_input'});
	}
    }

    # check defoutput
    if (defined $fileConfig->{'def_output'}) {
	if ($curConfig{'def_output'} ne $fileConfig->{'def_output'}) {
	    print("DBG: default output has changed\n");
	    my ($nName, $n) = getnode(\%curExtract, $fileConfig->{'def_output'});
	    print("DBG: pactl set-default-sink $n->{'devId'}\n");
	    system("pactl set-default-sink $n->{'devId'}\n");
	} else {
	    printf("def sink is OK: %s\n", $fileConfig->{'def_output'});
	}
    }

    # print("DBG: pactl move-source-output $sourceId $id\n");

    # check each node (volume)

    # check each loopback
    # don't care about the order in the long term :/
    # but keep it consistent accross each run 
    my @fileLoop = ();
    my @curLoop = ();
    if (defined $fileConfig->{'loopback'}) {
	my $h =$fileConfig->{'loopback'};
	my @skeys = sort keys %{$h};
	@fileLoop = @$h{@skeys};
    }

    if (defined $curConfig{'loopback'}) {
	my $h = $curConfig{'loopback'};
	my @skeys = sort keys %{$h};
	@curLoop = @$h{@skeys};
    }

    # add loopback if needed then restart the detection
    for(my $i=0; $i < scalar(@fileLoop) - scalar(@curLoop); $i++) {
	system("pactl load-module module-loopback");
	$rc = 0;
    }
    if (not $rc) {
	return $rc;
    }

    for(my $i=0; $i < scalar(@fileLoop); $i++) {
	printf("Checking loopback %d (%s)\n", $i, $fileLoop[$i]->{'desc'});
	my $tryCnt = 0;
	my $tryMax = @{$fileLoop[$i]->{'dst'}};
	foreach my $dstName ( @{$fileLoop[$i]->{'dst'}} ) {
	    $tryCnt++;
	    my ($tName, $tObj) = getnode(\%curExtract, $dstName);

	    if (not defined $tName) {
		printf("[%s] Attempt [%d/%d]: dest not found: $dstName\n", $fileLoop[$i]->{'desc'} , $tryCnt, $tryMax);
	    } else {
		printf("[%s] Attempt [%d/%d]: dest found: $dstName\n", $fileLoop[$i]->{'desc'}, $tryCnt, $tryMax);

		if ($dstName ne $curLoop[$i]->{'dst'}[0]) {
		    print("update needed\n");
		    my $sinkId = $tObj->{'devId'};
		    my $id = $curLoop[$i]->{'sinkId'};
		    print("DBG: pactl move-sink-input $id $sinkId\n"); # sourceid , id
		    system("pactl move-sink-input $id $sinkId\n"); # sourceid , id
		} else {
		    printf("[%s] Attempt [%d/%d]: no action needed\n", $fileLoop[$i]->{'desc'}, $tryCnt, $tryMax);
		}
		last;
	    }
	}

	$tryCnt = 0;
	$tryMax = @{$fileLoop[$i]->{'dst'}};
	foreach my $srcName ( @{$fileLoop[$i]->{'src'}} ) {
	    $tryCnt++;
	    my ($tName, $tObj) = getnode(\%curExtract, $srcName);

	    if (not defined $tName) {
		printf("[%s] Attempt [%d/%d]: src not found: $srcName\n", $fileLoop[$i]->{'desc'} , $tryCnt, $tryMax);
	    } else {
		printf("[%s] Attempt [%d/%d]: src found: $srcName\n", $fileLoop[$i]->{'desc'}, $tryCnt, $tryMax);

		if ($srcName ne $curLoop[$i]->{'src'}[0]) {
		    print("update needed\n");
		    my $dstId = $tObj->{'devId'};
		    my $id = $curLoop[$i]->{'sourceId'};
		    print("DBG: pactl move-source-output $id $dstId\n"); # sourceid , id
		    system("pactl move-source-output $id $dstId\n"); # sourceid , id
		} else {
		    printf("[%s] Attempt [%d/%d]: no action needed\n", $fileLoop[$i]->{'desc'}, $tryCnt, $tryMax);
		}
		last;
	    }
	}
    }

    return $rc;
}

__END__
=encoding utf8

=head1 NAME

pactl-loopmgt.pl - manage PulseAudio/Pipewire loop devices

=head1 SYNOPSYS

=over 12

=item B<pactl-loopmgt.pl>
[B<-h|--help>]
[B<-m|--man>]
[B<-f|--file>]
[B<-t|--table>]
[B<-j|--json>]
[B<-d|--daemon>]

=back

=head1 DESCRIPTION

This tool is a wrapper around "pactl". It can create and manage the input and
output of loop devices, manage the sound volume and manage defaults input and
output devices. It supports both USB and Bluetooth devices.

Some of the additional features of pactl-loopmgt.pl are:

=over 8

=item display the running configuration in a tabular

=item export the running configuration in json

=item apply the configuration saved in a json file

=item handle multiple input/output per loopdevice (by priority order)

=item daemon mode

=item force volume settings

=back

=head1 OPTIONS


=over 8

=item B<-h|--help>

Print a brief help message and exit.

=item B<-m|--man>

Print the full manual page and exit.

=item B<-f|file>

JSON configuration file. A template can be generated with the option "--json".

=item B<-t|table>

Print the running configuration in an extra large tabular.

=item B<-j|json>

Generate a JSON configuration template based on the current running configuration.

=item B<-d|daemon>

Do not exit after the first configuration but listen for any event in Pipewire.
After each event the rules will be reevaluated.

=back


=head1 CAVEATS

=over 8

=item File format may slighly change in the future.

=back


=head1 EXAMPLES

=head2 DAEMON

    pactl-loopmgt.pl -d -f config-file.json

=head1 HOWTO

The simplest way to configure pactl-loopmgt.pl is to create the desired configuration using
an other tool (see L<SEE ALSO>). Then, use pactl-loopmgt.pl to save and recall the configuration:

    pactl-loopmgt.pl --json > config-file.json
    pactl-loopmgt.pl -d -f config-file.json

The JSON file must look like:

    {
	"loopback": {
	    "loopback-3568-13": {
		"desc": "loopback-3568-13",
		"dst": [
		    "bluez_output.01_17_D1_AE_1E_7D.2",
		    "alsa_output.pci-0000_08_00.1.hdmi-stereo-extra1"
		],
		"src": [
		    "alsa_input.pci-0000_0a_00.4.analog-stereo"
		],
		"sinkId": 73512,
		"sourceId": 73513
	    }
	},
	"nodes": {
	    "alsa_output.pci-0000_08_00.1.hdmi-stereo-extra1": {
		"base_volume": "100%",
		"devId": 73540,
		"desc": "Monitor of Navi 31 HDMI/DP Audio Digital Stereo (HDMI 2)"
	    },
	    "alsa_input.pci-0000_0a_00.4.analog-stereo": {
		"devId": 27322,
		"desc": "Starship/Matisse HD Audio Controller",
		"base_volume": "10%"
	    }
	},
	"def_input": "alsa_input.pci-0000_0a_00.4.analog-stereo",
	"def_output": "alsa_output.pci-0000_08_00.1.hdmi-stereo-extra1"
    }

=over 8

=item All device ids are kept for debuging and can be safely removed.

=item Loopback "dst" and "src" attributes are JSON arrays.

=over 16

=item The attribute is set to the first device found.

=item It can be used to automatically handle USB and Bluetooth device connection.

=back

=item If set, the "base_volume" will be enforced.

=back

=head1 TODO List

=over 8

=item Manage B<def_input> and B<def_output> with arrays.

=item Manage latency

=item Manage sink_input (client programs)

=over 16

=item auto detection

=item patter matching on the name

=item volume

=item output devices

=back

=back

=head1 COPYRIGHT

Permission to use, copy, modify, distribute, and sell this software and its
documentation for any purpose is hereby granted without fee, provided that
the above copyright notice appear in all copies and that both that
copyright notice and this permission notice appear in supporting
documentation.  No representations are made about the suitability of this
software for any purpose.  It is provided "as is" without express or
implied warranty.

=head1 SEE ALSO

=over 8

=item L<pavucontrol|https://freedesktop.org/software/pulseaudio/pavucontrol/>

GTK based mixer for Pulseaudio and Pipewire.

=item L<wireplumber|https://gitlab.freedesktop.org/pipewire/wireplumber>

Modular session / policy manager for PipeWire.

=item wpctl

Command line utility provided with Wireplumber.

=item L<pactl|https://www.freedesktop.org/wiki/Software/PulseAudio/>

Command line tool from libpulse used has backend for this script.

=back

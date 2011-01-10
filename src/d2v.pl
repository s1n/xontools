#!/usr/bin/perl

use warnings;
use strict;
use feature "say";
use Getopt::Long;
use Pod::Usage;
use File::Find::Rule;
use Cwd qw/abs_path/;

sub parse_opts {
   my ($optsref) = @_;
   #do the grunt work of parsing
   GetOptions($optsref, 'cfg=s',
                        'demo=s',
                        'dpexe=s',
                        'dppath=s',
                        'transcoder=s',
                        'vid_codec=s',
                        'vid_opts',
                        'vid_scale=s',
                        'vid_bydate',
                        'snd_codec=s',
                        'outfile=s',
                        'threads=i',
                        'logfile=s',
                        'pretend',
                        'capture!',
                        'transcode!',
                        'log!',
                        'debug',
                        'help') or pod2usage(2);
   $optsref->{transcode} //= 1;
   $optsref->{capture} //= 1;
   #handle some error conditions
   pod2usage(1) if $optsref->{help};
   pod2usage(1) if !$optsref->{demo} && $optsref->{capture};

   #set some defaults
   $optsref->{vid_scale} //= '640x480';
   if($optsref->{vid_scale} !~ /^\d+x\d+$/) {
      die "Invalid vid_scale format: $optsref->{vid_scale}\n";
   }
   $optsref->{vid_scale} =~ s/^(\d+)x(\d+)$/$1:$2/;
   $optsref->{dpexe} //= 'nexuiz-glx';
   $optsref->{transcoder} //= 'mencoder';
   $optsref->{threads} //= 4;
   #use the logfile, else write everything to stderr
   if($optsref->{logfile} || $optsref->{log}) {
      $optsref->{logfile} //= "$optsref->{demo}.log";
      open $optsref->{logfd}, ">$optsref->{logfile}" or
         die "Unable to open logfile: $optsref->{logfile}: $!\n";
   } else {
      $optsref->{logfd} = \*STDERR;
   }
   if(!$optsref->{vid_codec}) {
      $optsref->{vid_codec} = 'xvid';
      $optsref->{vid_opts} //= "-xvidencopts chroma_opt:vhq=4:bvhq=1:quant_type=mpeg:fixed_quant=1:threads=$optsref->{threads}";
   }
   $optsref->{snd_codec} //= 'pcm';
   $optsref->{outfile} //= 'video.out';
   my $d = $optsref->{dpexe};
   $d =~ s/-.*//;
   $optsref->{dppath} //= "$ENV{HOME}/.$d/data";
   if($optsref->{capture}) {
      $optsref->{demo} = abs_path($optsref->{demo});
      $optsref->{demo} =~ s/$optsref->{dppath}\///;
   }

   if($optsref->{debug}) {
      say {$optsref->{logfd}} "Using options:";
      while(my ($key, $value) = each %$optsref) {
         my $v = $value // 'undef';
         say {$optsref->{logfd}} "   $key => $v";
      }
   }
}

sub capturevideo {
   my ($optsref) = @_;
   #build the executable command
   my $exe = $optsref->{dpexe};
   $exe .= " +exec $optsref->{cfg}" if $optsref->{cfg};
   $exe .= " +cl_capturevideo 1 -demo $optsref->{demo}";

   #log and execute darkplaces
   say {$optsref->{logfd}} "$exe" if $optsref->{debug};
   if(!$optsref->{vid_bydate}) {
      #find the line from the log, don't know if this is the best idea yet
      my @output = `$exe 2>&1`;
      for my $line(@output) {
         if($line =~ /Finishing capture of (\S+)\s.*/) {
            $optsref->{vid_tmp} = "$optsref->{dppath}/$1";
         }
      }
   } else {
      print {$optsref->{logfd}} `$exe 2>&1` if !$optsref->{pretend};
   }
}

sub transcode {
   my ($optsref) = @_;
   #find the newest file by reverse sorting the modification date
   my $dir = "$optsref->{dppath}/video";

   if($optsref->{vid_bydate}) {
      opendir DPDIR, $dir or 
         die "Unable to locate DarkPlaces video path ($dir): $!\n";
      my @sortedfiles = sort {-M "$dir/$b" <=> -M "$dir/$a"}
                        grep { !/^\.$/ }
                        readdir(DPDIR);
      closedir DPDIR;
      $optsref->{vid_tmp} = "$dir/$sortedfiles[-1]";
   }
   if($optsref->{debug}) {
      say {$optsref->{logfd}} "Latest captured demo file: $optsref->{vid_tmp}";
   }

   #build the executable command
   my $exe = $optsref->{transcoder};
   $exe .= " -o $optsref->{outfile}";
   $exe .= " -ovc $optsref->{vid_codec}";
   $exe .= " $optsref->{vid_opts}" if $optsref->{vid_opts};
   $exe .= " -oac $optsref->{snd_codec}";
   $exe .= " -vf scale=$optsref->{vid_scale}";
   $exe .= " $optsref->{vid_tmp}";

   #log and execute the transcoder
   say {$optsref->{logfd}} "$exe" if $optsref->{debug};
   print {$optsref->{logfd}} `$exe 2>&1` if !$optsref->{pretend};
}

sub cleanup {
   my ($optsref) = @_;
   if($optsref->{debug} && $optsref->{vid_tmp}) {
      say {$optsref->{logfd}} "Removing temp video file: $optsref->{vid_tmp}";
   }
   close $optsref->{logfd} if $optsref->{logfd};
   if(!$optsref->{pretend} && $optsref->{transcode} && $optsref->{vid_tmp}) {
      unlink $optsref->{vid_tmp};
   }
}

my %opts;

parse_opts(\%opts);
capturevideo(\%opts) if $opts{capture};
transcode(\%opts) if $opts{transcode};
cleanup(\%opts);

__END__

=head1 NAME

d2v - DarkPlaces to portable video format converter.

=head1 SYNOPSIS

d2v.pl [options]

 Options:
   --help           Display brief help message.
   --outfile file   Sets the output video filename.
   --cfg file       Adds a config file to video capture.
   --demo file      Adds a DarkPlaces demo to convert.
   --dpexe bin      Sets the name of the DarkPlaces binary.
   --dppath path    Sets the path to the DarkPlaces data directory.
   --transcoder bin Sets the transcoder application binary.
   --vid_codec c    Sets the output video codec.
   --vid_opts o     Sets additional video codec options.
   --vid_scale WxH  Sets a rescaling size when transcoding.
   --vid_bydate     Find the captured video by date.
   --snd_codec c    Sets the sound codec format.
   --threads i      Sets the number of transcoding threads.
   --logfile file   Sets a log file.
   --[no]capture    Enable/disable video capturing phase.
   --[no]transcode  Enable/disable video transcoding phase.
   --[no]log        Enable disable logging.
   --debug          Verbose debug output.

=head1 OPTIONS

=over 4

=item B<--help>

Display brief help message.

=item B<--outfile file>

Sets the output video filename. The output filename is not modified and is used
directly in whatever way specified. Defaults to 'video.out'.

=item B<--cfg file>

Adds a config file to video capture. When launching DarkPlaces, this will set
a config file, which should contain things like capture specific controls,
quality settings, or on-screen elements.

=item B<--demo file>

Adds a DarkPlaces demo to convert. This is the demo file created by the
DarkPlaces engine. This should be a regular filename, but may be a DarkPlaces
data folder specific name. That is, it may or may not contain the B<--dppath>
path value.

=item B<--dpexe bin>

Sets the name of the DarkPlaces binary. Defaults to 'nexuiz-glx'.

=item B<--dppath path>

Sets the path to the DarkPlaces data directory. Defaults to '~/nexuiz/data'.

=item B<--transcoder bin>

Sets the transcoder application binary. Defaults to 'mencoder'.

=item B<--vid_codec c>

Sets the output video codec. This codec name must be supported by the
B<--transcoder> application. Defaults to 'xvid'.

=item B<--vid_opts o>

Sets additional video codec options. These options must be supported by the
B<--transocder> application and must correspond to the B<--vid_codec> option.
Default options selected to match the default B<--vid_codec>; use the
B<--pretend> and B<--debug> options to see the full default value.

=item B<--vid_scale WxH>

Sets a rescaling size when transcoding. This should be specified in the format
'width x height', with no spaces. Assumes the B<--transcoder> application
will accept an option, B<--vf scale=width:height>. Defaults to '640x480'

=item B<--vid_bydate>

Find the captured video by date. When not performing the capture phase or when
the B<--dpexe> does not log the captured video correctly, this option will force
the latest video to be identified by the newest dated file. Defaults to enabled.

=item B<--snd_codec c>

Sets the sound codec format. Defaults to 'pcm'.

=item B<--threads i>

Sets the number of transcoding threads. Defaults to 4.

=item B<--logfile file>

Sets a log file. Defaults to writing the log data to stderr.

=item B<--[no]capture>

Enable/disable video capturing phase. Defaults to enabled (B<--capture>).

=item B<--[no]transcode>

Enable/disable video transcoding phase. Defaults to enabled (B<--transcode>).

=item B<--[no]log>

Enable disable logging. Defaults to enabled (B<--log>).

=item B<--debug>

Verbose debug output. Defaults to disabled.

=back

=cut

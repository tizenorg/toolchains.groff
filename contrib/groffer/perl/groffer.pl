#! /usr/bin/env perl

# groffer - display groff files

# Source file position: <groff-source>/contrib/groffer/perl/groffer.pl
# Installed position: <prefix>/bin/groffer

# Copyright (C) 2006, 2009 Free Software Foundation, Inc.
# Written by Bernd Warken.

# Last update: 5 Jan 2009

# This file is part of `groffer', which is part of `groff'.

# `groff' is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# `groff' is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

########################################################################

use strict;
use warnings;
#use diagnostics;

# temporary dir and files
use File::Temp qw/ tempfile tempdir /;

# needed for temporary dir
use File::Spec;

# for `copy' and `move'
use File::Copy;

# for fileparse, dirname and basename
use File::Basename;

# current working directory
use Cwd;

# $Bin is the directory where this script is located
use FindBin;


########################################################################
# system variables and exported variables
########################################################################

our $Dev_Null;
our $Umask;
our @Path;
our $Start_Dir;

our $tmpdir = '';
our ($fh_cat, $tmp_cat);
our ($fh_stdin, $tmp_stdin);

our @Addopts_Groff;
our %Debug;
our %Opt;

our $Has_Compression;
our $Has_bzip;

our $Output_File_Name;

our $Apropos_Prog;
our $Filespec_Arg;
our $Filespec_Is_Man;
our $Macro_Pkg;
our $Manspec;
our $No_Filespecs;
our $Special_Filespec;
our $Special_Setup;

our %Man;

BEGIN {
  $Dev_Null = File::Spec->devnull();

  $Umask = umask 077;

  $Start_Dir = getcwd;

  # flush after each print or write command
  $| = 1;
}


########################################################################
# read-only variables with double-@ construct
########################################################################

our $File_split_env_sh;
our $File_version_sh;
our $Groff_Version;

BEGIN {
  {
    my $before_make;		# script before run of `make'
    {
      my $at = '@';
      $before_make = 1 if '@VERSION@' eq "${at}VERSION${at}";
    }

    my %at_at;
    my $file_perl_test_pl;
    my $groffer_libdir;

    if ($before_make) {
      my $groffer_perl_dir = $FindBin::Bin;
      my $groffer_top_dir = File::Spec->catdir($groffer_perl_dir, '..');
      $groffer_top_dir = Cwd::realpath($groffer_top_dir);
      $at_at{'BINDIR'} = $groffer_perl_dir;
      $at_at{'G'} = '';
      $at_at{'LIBDIR'} = '';
      $groffer_libdir = $groffer_perl_dir;
      $file_perl_test_pl = File::Spec->catfile($groffer_perl_dir,
					       'perl_test.pl');
      $File_version_sh = File::Spec->catfile($groffer_top_dir, 'version.sh');
      $Groff_Version = '';
    } else {
      $Groff_Version = '@VERSION@';
      $at_at{'BINDIR'} = '@BINDIR@';
      $at_at{'G'} = '@g@';
      $at_at{'LIBDIR'} = '@libdir@';
      $groffer_libdir =
	File::Spec->catdir($at_at{'LIBDIR'}, 'groff', 'groffer');
      $file_perl_test_pl = File::Spec->catfile($groffer_libdir,
					       'perl_test.pl');
      $File_version_sh = File::Spec->catfile($groffer_libdir, 'version.sh');
    }

    die "$groffer_libdir is not an existing directory;"
      unless -d $groffer_libdir;

    unshift(@INC, $groffer_libdir);

    $File_split_env_sh = File::Spec->catfile($groffer_libdir, 'split_env.sh');
    die "$File_split_env_sh does not exist;" unless -f "$File_split_env_sh";

    # test perl on suitable version
    die "$file_perl_test_pl does not exist;" unless -f "$file_perl_test_pl";
    do "$file_perl_test_pl" or die "Perl test: $@";

    require 'func.pl';
    require 'man.pl';

    @Path = &path_uniq( File::Spec->path() );

    if ( &where_is_prog('gzip') ) {
      $Has_Compression = 1;
      $Has_bzip = 1 if &where_is_prog('bzip2');
    }
  }
}


########################################################################
# modes, viewers, man sections, and defaults
########################################################################

# configuration files
my @Conf_Files = (File::Spec->catfile(File::Spec->rootdir(),
				      'etc', 'groff', 'groffer.conf'),
		  File::Spec->catfile("$ENV{'HOME'}", '.groff',
				      'groffer.conf')
		 );

my @Default_Modes = ('pdf', 'html', 'ps', 'x', 'dvi', 'tty');
my $Default_Resolution = 75;
my $Default_tty_Device = 'latin1';

my @Macro_Packages = ('-man', '-mdoc', '-me', '-mm', '-mom', '-ms');

my %Viewer_tty = ('DVI' => [],
		  'HTML' => ['lynx', 'w3m'],
		  'PDF' => [],
		  'PS' => [],
		  'TTY' => ['less -r -R', 'more', 'pager'],
		  'X' => [],
		 );

my %Viewer_X =('DVI' => ['kdvi', 'xdvi', 'dvilx'],
	       'HTML' => ['konqueror', 'epiphany'. 'mozilla-firefox',
			  'firefox', 'mozilla', 'netscape', 'galeon', 'opera',
			  'amaya','arena', 'mosaic'],
	       'PDF' => ['kpdf', 'acroread', 'evince', 'xpdf -z 150', 'gpdf',
			 'kghostview --scale 1.45', 'ggv'],
	       'PS' => ['kpdf', 'kghostview --scale 1.45', 'evince', 'ggv',
			'gv', 'ghostview', 'gs_x11', 'gs'],
	       'TTY' => ['xless'],
	       'X' => ['gxditview', 'xditview'],
	      );

%Man = ('ALL' => 0,
	   'AUTO_SEC' => ['1', '2', '3', '4', '5', '6', '7', '8', '9',
			  'n', 'o'],
           'ENABLE' => 1,
	   'EXT' => '',
	   'FORCE' => 0,
	   'IS_SETUP' => 0,
	   'MANSPEC' => {},
	   'LANG' => '',
	   'LANG2' => '',
	   'PATH' => [],
	   'SEC' => [],
	   'SEC_CHARS' => '',
	   'SYS' => [],
	  );
$Man{'AUTO_SEC_CHARS'} = join('', @{$Man{'AUTO_SEC'}});


########################################################################
# given options, main_set_options()
########################################################################

my %Opts_Cmdline_Short;
my %Opts_Cmdline_Long;
my $Opts_Cmdline_Long_Str;
my %Opts_Cmdline_Double;
my %Opts_Groff_Short;

sub main_set_options {
  # the following options are ignored in groffer.pl, but are kept from
  # groffer.sh: --shell arg, --debug-shell

  my @opts_ignored_short_na = ();
  my @opts_ignored_short_arg = ();

  my @opts_ignored_long_na = ('debug-shell');

  my @opts_ignored_long_arg = ('shell');


  ###### groffer native options

  my @opts_groffer_short_na = ('h', 'Q', 'v', 'V', 'X', 'Z');
  my @opts_groffer_short_arg = ('T');

  my @opts_groffer_long_na = ('auto', 'apropos', 'apropos-data',
  'apropos-devel', 'apropos-progs', 'debug', 'debug-all',
  'debug-filenames', 'debug-func', 'debug-grog', 'debug-not-func',
  'debug-keep', 'debug-lm', 'debug-params', 'debug-stacks',
  'debug-tmpdir', 'debug-user', 'default', 'do-nothing', 'dvi',
  'groff', 'help', 'intermediate-output', 'html', 'man',
  'no-location', 'no-man', 'no-special', 'pdf', 'ps', 'rv', 'source',
  'text', 'to-stdout', 'text-device', 'tty', 'tty-device', 'version',
  'whatis', 'where', 'www', 'x', 'X');

### main_set_options()
  my @opts_groffer_long_arg = ('default-modes', 'device',
  'dvi-viewer', 'dvi-viewer-tty', 'extension', 'fg', 'fn', 'font',
  'foreground', 'html-viewer', 'html-viewer-tty', 'mode',
  'pdf-viewer', 'pdf-viewer-tty', 'print', 'ps-viewer',
  'ps-viewer-tty', 'title', 'tty-viewer', 'tty-viewer-tty',
  'www-viewer', 'www-viewer-tty', 'x-viewer', 'x-viewer-tty',
  'X-viewer', 'X-viewer-tty');

  ##### groffer options inhereted from groff

  my @opts_groff_short_na = ('a', 'b', 'c', 'C', 'e', 'E', 'g', 'G',
  'i', 'k', 'l', 'N', 'p', 'R', 's', 'S', 't', 'U', 'z');

  my @opts_groff_short_arg = ('d', 'f', 'F', 'I', 'K', 'L', 'm', 'M', 'n',
  'o', 'P', 'r', 'w', 'W');

  my @opts_groff_long_na = ();
  my @opts_groff_long_arg = ();

  ##### groffer options inhereted from the X Window toolkit

  my @opts_x_short_na = ();
  my @opts_x_short_arg = ();

  my @opts_x_long_na = ('iconic', 'rv');

  my @opts_x_long_arg = ('background', 'bd', 'bg', 'bordercolor',
  'borderwidth', 'bw', 'display', 'fg', 'fn', 'font', 'foreground',
  'ft', 'geometry', 'resolution', 'title', 'xrm');

### main_set_options()
  ###### groffer options inherited from man

  my @opts_man_short_na = ();
  my @opts_man_short_arg = ();

  my @opts_man_long_na = ('all', 'ascii', 'catman', 'ditroff',
  'local-file', 'location', 'troff', 'update');

  my @opts_man_long_arg = ('locale', 'manpath', 'pager',
  'preprocessor', 'prompt', 'sections', 'systems', 'troff-device');

  ###### additional options for parsing evironment variable $MANOPT only

  my @opts_manopt_short_na = ('7', 'a', 'c', 'd', 'D', 'f', 'h', 'k',
  'l', 't', 'u', 'V', 'w', 'Z');

  my @opts_manopt_short_arg = ('e', 'L', 'm', 'M', 'p', 'P', 'r', 'S',
  'T');

  my @opts_manopt_long_na = (@opts_man_long_na, 'apropos', 'debug',
  'default', 'help', 'html', 'ignore-case', 'location-cat',
  'match-case', 'troff', 'update', 'version', 'whatis', 'where',
  'where-cat');

  my @opts_manopt_long_arg = (@opts_man_long_na, 'config_file',
  'encoding', 'extension', 'locale');

### main_set_options()
  ###### collections of command line options

  # There are two hashes that control the whole of the command line
  # options, one for short and one for long options.  Options without
  # and with arguments are mixed by advicing a value of 0 for an option
  # without argument and a value of 1 for an option with argument.
  # The options are with leading minus.

  foreach (@opts_groffer_short_na, @opts_groff_short_na,
	   @opts_x_short_na, @opts_man_short_na, @opts_ignored_short_na) {
    $Opts_Cmdline_Short{"-$_"} = 0 if $_;
  }
  foreach (@opts_groffer_short_arg, @opts_groff_short_arg,
	   @opts_x_short_arg, @opts_man_short_arg, @opts_ignored_short_arg) {
    $Opts_Cmdline_Short{"-$_"} = 1 if $_;
  }

  foreach (@opts_groffer_long_na, @opts_groff_long_na,
	   @opts_x_long_na, @opts_man_long_na, @opts_ignored_long_na) {
    $Opts_Cmdline_Long{"--$_"} = 0 if $_;
  }
  foreach (@opts_groffer_long_arg, @opts_groff_long_arg,
	   @opts_x_long_arg, @opts_man_long_arg, @opts_ignored_long_arg) {
    $Opts_Cmdline_Long{"--$_"} = 1 if $_;
  }

  # For determining abbreviations of an option take two spaces as join
  # for better check.
  # The options are without leading minus.
  $Opts_Cmdline_Long_Str = join '  ', keys %Opts_Cmdline_Long;
  if ($Opts_Cmdline_Long_Str) {
    $Opts_Cmdline_Long_Str = " $Opts_Cmdline_Long_Str ";
    $Opts_Cmdline_Long_Str =~ s/--//g;
  }

### main_set_options()
  # options with equal meaning are mapped to a single option name
  # all of these have leading minus characters
  %Opts_Cmdline_Double = ('-h' => '--help',
			  '-Q' => '--source',
			  '-T' => '--device',
			  '-v' => '--version',
			  '-Z' => '--intermediate-output',
			  '--bd' => '--bordercolor',
			  '--bg' => '--background',
			  '--bw' => '--borderwidth',
			  '--debug-all' => '--debug',
			  '--ditroff' => '--intermediate-output',
			  '--dvi-viewer-tty' => '--dvi-viewer',
			  '--fg' => '--foreground',
			  '--fn' => '--font',
			  '--ft' => '--font',
			  '--html-viewer-tty' => '--html-viewer',
			  '--pdf-viewer-tty' => '--pdf-viewer',
			  '--ps-viewer-tty' => '--ps-viewer',
			  '--troff-device' => '--device',
			  '--tty-device' => '--text-device',
			  '--tty-viewer' => '--pager',
			  '--tty-viewer-tty' => '--pager',
			  '--where' => '--location',
			  '--www' => '--html',
			  '--www-viewer' => '--html-viewer',
			  '--www-viewer-tty' => '--html-viewer',
			  '--x-viewer-tty' => '--x-viewer',
			  '--X' => '--x',
			  '--X-viewer' => '--x-viewer',
			  '--X-viewer-tty' => '--x-viewer',
			 );

  # groff short options with leading minus
  foreach (@opts_groff_short_na) {
    $Opts_Groff_Short{"-$_"} = 0;
  }
  foreach (@opts_groff_short_arg) {
    $Opts_Groff_Short{"-$_"} = 1;
  }

}				# main_set_options()


########################################################################
# $MANOPT, main_parse_MANOPT()
########################################################################

# handle environment variable $MANOPT
my @Manopt;

sub main_parse_MANOPT {
  if ($ENV{'MANOPT'}) {
    @Manopt = `sh $File_split_env_sh MANOPT`;
    chomp @Manopt;

    my @manopt;
    # %opts stores options that are used by groffer for $MANOPT
    # All options not in %opts are ignored.
    # Check options used with %Opts_Cmdline_Double.
    # 0: option used ('' for ignore), 1: has argument or not
### main_parse_MANOPT()
    my %opts = ('-7' => ['--ascii', 0],
		'--ascii' => ['--ascii', 0],
		'-a' => ['--all', 0],
		'--all' => ['--all', 0],
		'-c' => ['', 1],
		'--catman' => ['', 1],
		'-e' => ['--extension', 1],
		'--extension' => ['--extension', 1],
		'-f' => ['--whatis', 1],
		'--whatis' => ['--whatis', 1],
		'-L' => ['--locale', 1],
		'--locale' => ['--locale', 1],
		'-m' => ['--systems', 1],
		'--systems' => ['--systems', 1],
		'-M' => ['--manpath', 1],
		'-manpath' => ['--manpath', 1],
		'--manpath' => ['--manpath', 1],
		'-p' => ['', 1],
		'--preprocessor' => ['', 1],
		'-P' => ['--pager', 1],
		'-pager' => ['--pager', 1],
		'-r' => ['', 1],
		'-prompt' => ['', 1],
		'-S' => ['--sections', 1],
		'-sections' => ['--sections', 1],
		'-T' => ['-T', 1],
		'--device' => ['-T', 1],
		'-w' => ['--location', 0],
		'--where' => ['--location', 0],
		'--location' => ['--location', 0],
	       );

### main_parse_MANOPT()
    my ($opt, $has_arg);
    my $i = 0;
    my $n = $#Manopt;
    while ($i <= $n) {
      my $o = $Manopt[$i];
      ++$i;
      # ignore, when not in %opts
      next unless (exists $opts{$o});
      if (($o eq '-D') or ($o eq '--default')) {
	@manopt = ();
	next;
      }
      $opt = $opts{$o}[0];
      $has_arg = $opts{$o}[1];
      # ignore, when empty in %opts
      unless ($opt) {
	# ignore without argument
	next unless ($has_arg);
	# ignore the argument as well
	++$i;
	next;
      }
      if ($has_arg) {
	last if ($i > $n);
	push @manopt, $opt, $Manopt[$i];
	++$i;
	next;
      } else {
	push @manopt, $opt;
	next;
      }
    }
    @Manopt = @manopt;
  }
}				# main_parse_MANOPT()


########################################################################
# configuration files, $GROFFER_OPT, and command line, main_config_params()
########################################################################

my @Options;
my @Filespecs;
my @Starting_Conf;
my @Starting_ARGV = @ARGV;
sub main_config_params {	# handle configuration files
  # options may not be abbreviated, but must be exact
  my @conf_args;
  foreach my $f (@Conf_Files) {
    if (-s $f) {
      my $fh;
      open $fh, "<$f" || next;
      my $nr = 0;
    LINE: foreach my $line (<$fh>) {
	++ $nr;
	chomp $line;
	# remove starting and ending whitespace
	$line =~ s/^\s+|\s+$//g;
	# replace whitespace by single space
	$line =~ s/\s+/ /g;
	# ignore all lines that do not start with minus
	next unless $line =~ /^-/;
	# three minus
	if ($line =~ /^---/) {
	  warn "Wrong option $line in configuration file $f.\n";
	  next;
	}
	if ($line =~ /^--[ =]/) {
	  warn "No option name in `$line' in configuration " .
	    "file $f.\n";
	  next;
	}
	push @Starting_Conf, $line;
	# -- or -
	if ($line =~ /^--?$/) {
	  warn "`$line' is not allowed in configuration files.\n";
	  next;
	}
	### main_config_params()
	if ($line =~ /^--/) {	# line is long option
	  my ($name, $arg);
	  if ($line =~ /[ =]/) { # has arg on line
	    $line =~ /^(--[^ =]+)[ =] ?(.*)$/;
	    ($name, $arg) = ($1, $2);
	    $arg =~ s/[\'\"]//g;
	  } else {		# does not have an argument on line
	    $name = $line;
	  }
	  $name =~ s/[\'\"]//g;
	  unless (exists $Opts_Cmdline_Long{$name}) {
	    # option does not exist
	    warn "Option `$name' does not exist.\n";
	    next LINE;
	  }
	  # option exists
	  if ($Opts_Cmdline_Long{$name}) { # option has arg
	    if (defined $arg) {
	      push @conf_args, $name, $arg;
	      next LINE;
	    } else {
	      warn "Option `$name' needs an argument in " .
		"configuration file $f\n";
	      next LINE;
	    }
	  } else {		# option has no arg
	    if (defined $arg) {
	      warn "Option `$name' may not have an argument " .
		"in configuration file $f\n";
	      next LINE;
	    } else {
	      push @conf_args, $name;
	      next LINE;
	    }
	  }
	  ### main_config_params()
	} else {		# line is short option or cluster
	  $line =~ s/^-//;
	  while ($line) {
	    $line =~ s/^(.)//;
	    my $opt = "-$1";
	    next if ($opt =~ /\'\"/);
	    if ($opt =~ /- /) {
	      warn "Option `$conf_args[$#conf_args]' does not " .
		"have an argument.\n";
	      next LINE;
	    }
	    if (exists $Opts_Cmdline_Short{$opt}) {
	      # short opt exists
	      push @conf_args, $opt;
	      if ($Opts_Cmdline_Short{$opt}) { # with arg
		my $arg = $line;
		$arg =~ s/^ //;
		$arg =~ s/\'\"//g;
		push @conf_args, "$arg";
		next LINE;
	      } else {		# no arg
		next;
	      }
	    } else {		# short option does not exist
	      warn "Wrong short option `-$opt' from " .
		"configuration.  Rest of line ignored.\n";
	      next LINE;
	    }
	  }
	}
      }
      close $fh;
    }
  }

### main_config_params()
  # handle environment variable $GROFFER_OPT
  my @GROFFER_OPT;
  if ($ENV{'GROFFER_OPT'}) {
    @GROFFER_OPT = `sh $File_split_env_sh GROFFER_OPT`;
    chomp @GROFFER_OPT;
  }

  # Handle command line parameters together with $GROFFER_OPT.
  # Options can be abbreviated, with each - as abbreviation place.
  {
    my @argv0 = (@GROFFER_OPT, @ARGV);
    my @argv;
    my $only_files = 0;
    my $n = $#argv0;		  # last element
    my $n1 = scalar @GROFFER_OPT; # first element of @ARGV
    my $i = 0;			# number of the element
    my @s = ('the environment variable $GROFFER_OPT', 'the command line');
    my $j = 0;			# index in @s, 0 before $n1, 1 then
  ELT: while ($i <= $n) {
      my $elt = $argv0[$i];
      $j = 1 if $i >= $n1;
      ++$i;
      # remove starting and ending whitespace
      $elt =~ s/^\s+|\s+$//g;
      # replace whitespace by single space
      $elt =~ s/\s+/ /g;

      if ($only_files) {
	push @Filespecs, $elt;
	next ELT;
      }

### main_config_params()
      if ($elt =~ /^-$/) {	# -
	push @Filespecs, $elt;
	next ELT;
      }
      if ($elt =~ /^--$/) {	# --
	$only_files = 1;
	next ELT;
      }

      if ($elt =~ /^--[ =]/) {	# no option name
	warn "No option name in `$elt' at $s[$j].\n";
	next ELT;
      }
      if ($elt =~ /^---/) {	# wrong with three minus
	warn "Wrong option `$elt' at $s[$j].\n";
	next ELT;
      }

      if ($elt =~ /^--[^-]/) {	# long option
	my ($name, $opt, $abbrev, $arg);
	if ($elt =~ /[ =]/) {	# has arg on elt
	  $elt =~ /^--([^ =]+)[ =] ?(.*)$/;
	  ($name, $arg) = ($1, $2);
	  $opt = "--$name";
	  $abbrev = $name;
	  $arg =~ s/[\'\"]//g;
	} else {		# does not have an argument in the element
	  $opt = $name = $elt;
	  $name =~ s/^--//;
	  $abbrev = $name;
	}
### main_config_params()
	# remove quotes in name
	$name =~ s/[\'\"]//g;
	my $match = $name;
	$match =~ s/-/[^- ]*-/g;
	### main_config_params()
	if (exists $Opts_Cmdline_Long{$opt}) {
	  # option exists exactly
	} elsif ($Opts_Cmdline_Long_Str =~ / (${match}[^- ]*?) /) {
	  # option is an abbreviation without further -
	  my $n0 = $1;
	  if ($Opts_Cmdline_Long_Str =~
	      / (${match}[^- ]*) .* (${match}[^- ]*) /) {
	    warn "Option name `--$abbrev' is not unique: " .
	      "--$1 --$2 \n";
	    next ELT;
	  }
	  $name = $n0;
	  $opt = "--$n0";
	} elsif ($Opts_Cmdline_Long_Str =~ / (${match}[^ ]*) /) {
	  # option is an abbreviation with further -
	  my $n0 = $1;
	  if ($Opts_Cmdline_Long_Str =~
	      / (${match}[^ ]*) .* (${match}[^ ]*) /) {
	    warn "Option name `--$abbrev' is not unique: " .
	      "--$1 --$2 \n";
	    next ELT;
	  }
	  $name = $n0;
	  $opt = "--$n0";
	} else {
	  warn "Option `--$abbrev' does not exist.\n";
	  next ELT;
	}
### main_config_params()
	if ($Opts_Cmdline_Long{$opt}) { # option has arg
	  if (defined $arg) {
	    push @argv, "--$name", $arg;
	    next ELT;
	  } else {		# $arg not defined, argument at next element
	    if (($i == $n1) || ($i > $n)) {
	      warn "No argument left for option " .
		"`$elt' at $s[$j].\n";
	      next ELT;
	    }
	    ### main_config_params()
	    # add argument as next element
	    push @argv, "--$name", $argv0[$i];
	    ++$i;
	    next ELT;
	  }			# if (defined $arg)
	} else {		# option has no arg
	  if (defined $arg) {
	    warn "Option `$abbrev' may not have an argument " .
	      "at $s[$j].\n";
	    next ELT;
	  } else {
	    push @argv, "--$name";
	    next ELT;
	  }
	}			# if ($Opts_Cmdline_Long{$opt})
### main_config_params()
      } elsif ($elt =~ /^-[^-]/) { # short option or cluster
	my $cluster = $elt;
	$cluster =~ s/^-//;
	while ($cluster) {
	  $cluster =~ s/^(.)//;
	  my $opt = "-$1";
	  if (exists $Opts_Cmdline_Short{$opt}) { # opt exists
	    if ($Opts_Cmdline_Short{$opt}) { # with arg
	      if ($cluster) {	# has argument in this element
		$cluster =~ s/^ //;
		$cluster =~ s/\'\"//g;
				# add argument as rest of this element
		push @argv, $opt, $cluster;
		next ELT;
	      } else {		# argument at next element
		if (($i == $n1) || ($i > $n)) {
		  warn "No argument left for option " .
		    "`$opt' at $s[$j].\n";
		  next ELT;
		}
		### main_config_params()
				# add argument as next element
		push @argv, $opt, $argv0[$i];
		++$i;
		next ELT;
	      }
	    } else {		# no arg
	      push @argv, $opt;
	      next;
	    }
	  } else {		# short option does not exist
	    warn "Wrong short option `$opt' at $s[$j].\n";
	    next ELT;
	  }			# if (exists $Opts_Cmdline_Short{$opt})
	}			# while ($cluster)
      } else {			# not an option, file name
	push @Filespecs, $elt;
	next;
      }
    }
### main_config_params()
    @Options = (@Manopt, @conf_args, @argv);
    foreach my $i (0..$#Options) {
      if ( exists $Opts_Cmdline_Double{ $Options[$i] } ) {
	$Options[$i] = $Opts_Cmdline_Double{ $Options[$i] };
      }
    }
    @Filespecs = ('-') unless (@Filespecs);
    @ARGV = (@Options, '--', @Filespecs);
  }
} # main_config_params()

if (0) {
  print STDERR "<$_>\n" foreach @ARGV;
}


########################################################################
# main_parse_params()
########################################################################

my $i;
my $n;

$Opt{'XRM'} = [];

sub main_parse_params {
  $i = 0;
  $n = $#Options;

  # options that are ignored in this part
  # shell version of groffer: --debug*, --shell
  # man options: --catman (only special in man),
  #              --preprocessor (force groff preproc., handled by grog),
  #              --prompt (prompt for less, ignored),
  #              --troff (-mandoc, handled by grog),
  #              --update (inode check, ignored)
  my %ignored_opts = (
		      '--catman' => 0,
		      '--debug-func' => 0,
		      '--debug-not-func' => 0,
		      '--debug-lm' => 0,
		      '--debug-shell' => 0,
		      '--debug-stacks' => 0,
		      '--debug-user' => 0,
		      '--preprocessor' => 1,
		      '--prompt' => 1,
		      '--shell' => 1,
		      '--troff' => 0,
		      '--update' => 0,
		     );

### main_parse_params()
  my %long_opts =
    (
     '--debug' =>
     sub { $Debug{$_} = 1 foreach (qw/FILENAMES GROG KEEP PARAMS TMPDIR/); },
     '--debug-filenames' => sub { $Debug{'FILENAMES'} = 1; },
     '--debug-grog' => sub { $Debug{'GROG'} = 1; },
     '--debug-keep' => sub { $Debug{'KEEP'} = 1; $Debug{'PARAMS'} = 1; },
     '--debug-params' => sub { $Debug{'PARAMS'} = 1; },
     '--debug-tmpdir' => sub { $Debug{'TMPDIR'} = 1; },
     '--help' => sub { &usage(); $Opt{'DO_NOTHING'} = 1; },
     '--source' => sub { $Opt{'MODE'} = 'source'; },
     '--device' =>
     sub {  $Opt{'DEVICE'} = &_get_arg();
	    my %modes = ( 'dvi'=> 'dvi',
			  'html' => 'html',
			  'lbp' => 'groff',
			  'lj4' => 'groff',
			  'ps' => 'ps',
			  'ascii' => 'tty',
			  'cp1047' => 'tty',
			  'latin1' => 'tty',
			  'utf8' => 'tty',
			);
	    if ($Opt{'DEVICE'} =~ /^X.*/) {
	      $Opt{'MODE'} = 'x';
	    } elsif ( exists $modes{ $Opt{'DEVICE'} } ) {
	      if ( $modes{ $Opt{'DEVICE'} } eq 'tty' ) {
		$Opt{'MODE'} = 'tty'
		  unless ($Opt{'MODE'} eq 'text');
	      } else {
		$Opt{'MODE'} = $modes{ $Opt{'DEVICE'} };
	      }
	    } else {
	      # for all elements not in %modes
	      $Opt{'MODE'} = 'groff';
	    }
	  },
### main_parse_params()
     '--version' => sub { &version(); $Opt{'DO_NOTHING'} = 1; },
     '--intermediate-output' => sub { $Opt{'Z'} = 1; },
     '--all' => sub { $Opt{'ALL'} = 1; },
     '--apropos' =>		# run apropos
     sub { $Opt{'APROPOS'} = 1;
	   delete $Opt{'APROPOS_SECTIONS'};
	   delete $Opt{'WHATIS'}; },
     '--apropos-data' =>	# run apropos for data sections
     sub { $Opt{'APROPOS'} = 1;
	   $Opt{'APROPOS_SECTIONS'} = '457';
	   delete $Opt{'WHATIS'}; },
     '--apropos-devel' =>	# run apropos for devel sections
     sub { $Opt{'APROPOS'} = 1;
	   $Opt{'APROPOS_SECTIONS'} = '239';
	   delete $Opt{'WHATIS'}; },
     '--apropos-progs' =>	# run apropos for prog sections
     sub { $Opt{'APROPOS'} = 1;
	   $Opt{'APROPOS_SECTIONS'} = '168';
	   delete $Opt{'WHATIS'}; },
     '--ascii' =>
     sub { push @Addopts_Groff, '-mtty-char';
	   $Opt{'MODE'} = 'text' unless $Opt{'MODE'}; },
     '--auto' =>		# the default automatic mode
     sub { delete $Opt{'MODE'}; },
     '--bordercolor' =>		# border color for viewers, arg
     sub { $Opt{'BD'} = &_get_arg(); },
     '--background' =>		# background color for viewers, arg
     sub { $Opt{'BG'} = &_get_arg(); },
### main_parse_params()
     '--borderwidth' =>		# border width for viewers, arg
     sub { $Opt{'BW'} = &_get_arg(); },
     '--default' =>		# reset variables to default
     sub { %Opt = (); },
     '--default-modes' =>	# sequence of modes in auto mode; arg
     sub { $Opt{'DEFAULT_MODES'} = &_get_arg(); },
     '--display' =>		# set X display, arg
     sub { $Opt{'DISPLAY'} = &_get_arg(); },
     '--do-nothing' => sub { $Opt{'DO_NOTHING'} = 1; },
     '--dvi' => sub { $Opt{'MODE'} = 'dvi'; },
     '--dvi-viewer' =>		# viewer program for dvi mode; arg
     sub { $Opt{'VIEWER_DVI'} = &_get_arg(); },
     '--extension' =>		# the extension for man pages, arg
     sub { $Opt{'EXTENSION'} = &_get_arg(); },
     '--foreground' =>		# foreground color for viewers, arg
     sub { $Opt{'FG'} = &_get_arg(); },
     '--font' =>		# set font for viewers, arg
     sub { $Opt{'FN'} = &_get_arg(); },
     '--geometry' =>		# window geometry for viewers, arg
     sub { $Opt{'GEOMETRY'} = &_get_arg(); },
     '--groff' => sub { $Opt{'MODE'} = 'groff'; },
     '--html' => sub { $Opt{'MODE'} = 'html'; },
     '--html-viewer' =>		# viewer program for html mode; arg
     sub { $Opt{'VIEWER_HTML'} = &_get_arg(); },
     '--iconic' =>		# start viewers as icons
     sub { $Opt{'ICONIC'} = 1; },
     '--locale' =>		# set language for man pages, arg
     # argument is xx[_territory[.codeset[@modifier]]] (ISO 639,...)
     sub { $Opt{'LANG'} = &_get_arg(); },
     '--local-file' =>		# force local files; same as `--no-man'
     sub { delete $Man{'ENABLE'}; delete $Man{'FORCE'}; },
     '--location' =>		# print file locations to stderr
     sub { $Opt{'LOCATION'} = 1; },
### main_parse_params()
     '--man' =>			# force all file params to be man pages
     sub { $Man{'ENABLE'} = 1; $Man{'FORCE'} = 1; },
     '--manpath' =>		# specify search path for man pages, arg
     # arg is colon-separated list of directories
     sub { $Opt{'MANPATH'} = &_get_arg(); },
     '--mode' =>		# display mode
     sub { my $arg = &_get_arg();
	   my %modes = ( '' => '',
			 'auto' => '',
			 'groff' => 'groff',
			 'html' => 'html',
			 'www' => 'html',
			 'dvi' => 'dvi',
			 'pdf' => 'pdf',
			 'ps' => 'ps',
			 'text' => 'text',
			 'tty' => 'tty',
			 'X' => 'x',
			 'x' => 'x',
			 'Q' => 'source',
			 'source' => 'source',
		       );
	   if ( exists $modes{$arg} ) {
	     if ( $modes{$arg} ) {
	       $Opt{'MODE'} = $modes{$arg};
	     } else {
	       delete $Opt{'MODE'};
	     }
	   } else {
	     warn "Unknown mode in `$arg' for --mode\n";
	   }
	 },
### main_parse_params()
     '--no-location' =>		# disable former call to `--location'
     sub { delete $Opt{'LOCATION'}; },
     '--no-man' =>		# disable search for man pages
     sub { delete $Man{'ENABLE'}; delete $Man{'FORCE'}; },
     '--no-special' =>		# disable some special former calls
     sub { delete $Opt{'ALL'}; delete $Opt{'APROPOS'};
	   delete $Opt{'WHATIS'}; },
     '--pager' =>		# set paging program for tty mode, arg
     sub { $Opt{'PAGER'} = &_get_arg(); },
     '--pdf' => sub { $Opt{'MODE'} = 'pdf'; },
     '--pdf-viewer' =>		# viewer program for pdf mode; arg
     sub { $Opt{'VIEWER_PDF'} = &_get_arg(); },
     '--print' =>		# print argument, for argument test
     sub { my $arg = &_get_arg; print STDERR "$arg\n"; },
     '--ps' => sub { $Opt{'MODE'} = 'ps'; },
     '--ps-viewer' =>		# viewer program for ps mode; arg
     sub { $Opt{'VIEWER_PS'} = &_get_arg(); },
     '--resolution' =>		# set resolution for X devices, arg
     sub { my $arg = &_get_arg();
	   my %res = ( '75' => 75,
		       '75dpi' => 75,
		       '100' => 100,
		       '100dpi' => 100,
		     );
	   if (exists $res{$arg}) {
	     $Opt{'RESOLUTION'} = $res{$arg};
	   } else {
	     warn "--resolution allows only 75, 75dpi, " .
	       "100, 100dpi as argument.\n";
	   }
	 },
### main_parse_params()
     '--rv' => sub { $Opt{'RV'} = 1; },
     '--sections' =>		# specify sections for man pages, arg
     # arg is a `:'-separated (colon) list of section names
     sub { my $arg = &_get_arg();
	   my @arg = split /:/, $arg;
	   my $s;
	   foreach (@arg) {
	     /^(.)/;
	     my $c = $1;
	     if ($Man{'AUTO_SEC_CHARS'} =~ /$c/) {
	       $s .= $c;
	     } else {
	       warn "main_parse_params(): not a man section `$c';";
	     }
	   }
	   $Opt{'SECTIONS'} = $s; },
     '--systems' =>		# man pages for different OS's, arg
     # argument is a comma-separated list
     sub { $Opt{'SYSTEMS'} = &_get_arg(); },
     '--text' =>		# text mode without pager
     sub { $Opt{'MODE'} = 'text'; },
     '--title' =>		# title for X viewers; arg
     sub { my $arg = &_get_arg();
	   if ($arg) {
	     if ( $Opt{'TITLE'} ) {
	       $Opt{'TITLE'} = "$Opt{'TITLE'} $arg";
	     } else {
	       $Opt{'TITLE'} = $arg;
	     }
	   }
	 },
     '--tty' =>			# tty mode, text with pager
     sub { $Opt{'MODE'} = 'tty'; },
     '--to-stdout' =>		# print mode file without display
     sub { $Opt{'STDOUT'} = 1; },
     '--text-device' =>		# device for tty mode; arg
     sub { $Opt{'TEXT_DEVICE'} = &_get_arg(); },
     '--whatis' => sub { delete $Opt{'APROPOS'}; $Opt{'WHATIS'} = 1; },
     '--x' => sub { $Opt{'MODE'} = 'x'; },
### main_parse_params()
     '--xrm' =>			# pass X resource string, arg
     sub { my $arg = &_get_arg(); push @{$Opt{'XRM'}}, $arg if $arg; },
     '--x-viewer' =>		# viewer program for x mode; arg
     sub { $Opt{'VIEWER_X'} = &_get_arg(); },
    );

  my %short_opts = (
		    '-V' => sub { $Opt{'V'} = 1; },
		    '-X' => sub { $Opt{'X'} = 1; },
		   );

  if (0) {
    # check if all options are handled in parse parameters

    #short options
    my %these_opts = (%ignored_opts, %short_opts, %Opts_Groff_Short,
		      %Opts_Cmdline_Double);
    foreach my $key (keys %Opts_Cmdline_Short) {
      warn "unused option: $key" unless exists $these_opts{$key};
    }

    # long options
    %these_opts = (%ignored_opts, %long_opts, %Opts_Cmdline_Double);
    foreach my $key (keys %Opts_Cmdline_Long) {
      warn "unused option: $key" unless exists $these_opts{$key};
    }
  }				# if (0)

### main_parse_params()
 OPTION: while ($i <= $n) {
    my $opt = $Options[$i];
    ++$i;
    if ($opt =~ /^-([^-])$/) {	# single minus for short option
      if (exists $short_opts{$opt}) { # short option handled by hash
	$short_opts{$opt}->();
	next OPTION;
      } else {			# $short_opts{$opt} does not exist
	my $c = $1;		# the option character
	next OPTION unless $c;
	if ( exists $Opts_Groff_Short{ $opt } ) { # groff short option
	  if ( $Opts_Groff_Short{ $opt } ) { # option has argument
	    my $arg = $Options[$i];
	    ++$i;
	    push @Addopts_Groff, $opt, $arg;
	    next OPTION;
	  } else {		# no argument for this option
	    push @Addopts_Groff, $opt;
	    next OPTION;
	  }
	} elsif ( exists $Opts_Cmdline_Short{ $opt } ) {
	  # is a groffer short option
	  warn "Groffer option $opt not handled " .
	    "in parameter parsing";
	} else {
	  warn "$opt is not a groffer option.\n";
	}
      }				# if (exists $short_opts{$opt})
    }				# if ($opt =~ /^-([^-])$/)
    # Now it is a long option

    # handle ignored options
    if ( exists $ignored_opts{ $opt } ) {
      ++$i if ( $ignored_opts{ $opt } );
      next OPTION;
    }
### main_parse_params()

    # handle normal long options
    if (exists $long_opts{$opt}) {
      $long_opts{$opt}->();
    } else {
      warn "Unknown option $opt.\n";
    }
    next OPTION;
  }				# while ($i <= $n)

  if ($Debug{'PARAMS'}) {
    print STDERR '$MANOPT: ' . "$ENV{'MANOPT'}\n" if $ENV{'MANOPT'};
    foreach (@Starting_Conf) {
      print STDERR "configuration: $_\n";
    }
    print STDERR '$GROFFER_OPT: ' . "$ENV{'GROFFER_OPT'}\n"
      if $ENV{'GROFFER_OPT'};
    print STDERR "command line: @Starting_ARGV\n";
    print STDERR "parameters: @ARGV\n";
  }

  if ( $Opt{'WHATIS'} ) {
    die "main_parse_params(): cannot handle both `whatis' and `apropos';"
      if $Opt{'APROPOS'};
    $Man{'ALL'} = 1;
    delete $Opt{'APROPOS_SECTIONS'};
  }

  if ( $Opt{'DO_NOTHING'} ) {
    exit;
  }

  if ( $Opt{'DEFAULT_MODES'} ) {
    @Default_Modes = split /,/, $Opt{'DEFAULT_MODES'};
  }
}				# main_parse_params()


sub _get_arg {
  if ($i > $n) {
    die '_get_arg(): No argument left for last option;';
  }
  my $arg = $Options[$i];
  ++$i;
  $arg;
}				# _get_arg() of main_parse_params()


########################################################################
# main_set_mode()
########################################################################

my $Viewer_Background;
my $PDF_Did_Not_Work;
my $PDF_Has_gs;
my $PDF_Has_ps2pdf;
my %Display = ('MODE' => '',
	       'PROG' => '',
	       'ARGS' => ''
	      );

sub main_set_mode {
  my @modes;

  # set display
  $ENV{'DISPLAY'} = $Opt{'DISPLAY'} if $Opt{'DISPLAY'};

  push @Addopts_Groff, '-V' if $Opt{'V'};

  if ( $Opt{'X'} ) {
    $Display{'MODE'} = 'groff';
    push @Addopts_Groff, '-X';
  }

  if ( $Opt{'Z'} ) {
    $Display{'MODE'} = 'groff';
    push @Addopts_Groff, '-Z';
  }

  $Display{'MODE'} = 'groff' if $Opt{'MODE'} and $Opt{'MODE'} eq 'groff';

  return 1 if $Display{'MODE'} and $Display{'MODE'} eq 'groff';

### main_set_mode()
  if ($Opt{'MODE'}) {
    if ($Opt{'MODE'} =~ /^(source|text|tty)$/) {
      $Display{'MODE'} = $Opt{'MODE'};
      return 1;
    }
    $Display{'MODE'} = $Opt{'MODE'} if $Opt{'MODE'} =~ /^html$/;
    @modes = ($Opt{'MODE'});
  } else {			# empty mode
    if ($Opt{'DEVICE'}) {
      if ($Opt{'DEVICE'} =~ /^X/) {
	&is_X() || die "no X display found for device $Opt{'DEVICE'}";
	$Display{'MODE'} = 'x';
	return 1;
      }
      ;
      if ($Opt{'DEVICE'} =~ /^(ascii|cp1047|latin1|utf8)$/) {
	$Display{'MODE'} ne 'text' and $Display{'MODE'} = 'tty';
	return 1;
      }
      ;
      unless (&is_X) {
	$Display{'MODE'} = 'tty';
	return 1;
      }
    }				# check device
    @modes = @Default_Modes;
  }				# check mode

### main_set_mode()
 LOOP: foreach my $m (@modes) {
    $Viewer_Background = 0;
    if ($m =~ /^(test|tty|X)$/) {
      $Display{'MODE'} = $m;
      return 1;
    } elsif ($m eq 'pdf') {
      next LOOP if $PDF_Did_Not_Work;
      $PDF_Has_gs = &where_is_prog('gs') ? 1 : 0
	unless (defined $PDF_Has_gs);
      $PDF_Has_ps2pdf = &where_is_prog('ps2pdf') ? 1 : 0
	unless (defined $PDF_Has_ps2pdf);
      if ( (! $PDF_Has_gs) and (! $PDF_Has_ps2pdf) ) {
	$PDF_Did_Not_Work = 1;
	next LOOP;
      }

      if (&_get_prog_args($m)) {
	return 1;
      } else {
	$PDF_Did_Not_Work = 1;
	next LOOP;
      }
    } else {			# other modes
      &_get_prog_args($m) ? return 1 : next LOOP;
    }				# if $m
  }				# LOOP: foreach
  die 'set mode: no suitable display mode found under ' .
    join(', ', @modes) . ';' unless $Display{'MODE'};
  die 'set mode: no viewer available for mode ' . $Display{'MODE'} . ';'
    unless $Display{'PROG'};
  0;
} # main_set_mode()


########################################################################
# functions to main_set_mode()
########################################################################

##########
# _get_prog_args(<MODE>)
#
# Simplification for loop in set mode.
#
# Globals in/out: $Viewer_Background
# Globals in    : $Opt{VIEWER_<MODE>}, $Viewer_X{<MODE>},
#                 $Viewer_tty{<MODE>}
#
sub _get_prog_args {
  my $n = @_;
  die "_get_prog_args(): one argument is needed; you used $n;"
    unless $n == 1;

  my $mode = lc($_[0]);
  my $MODE = uc($mode);

  my $xlist = $Viewer_X{$MODE};
  my $ttylist = $Viewer_tty{$MODE};

  my $vm = "VIEWER_${MODE}";
  my $opt = $Opt{$vm};

  if ($opt) {
    my %prog = where_is_prog $opt;
    my $prog_ref = \%prog;
    unless (%prog) {
      warn "_get_prog_args(): `$opt' is not an existing program;";
      return 0;
    }

    # $prog from $opt is an existing program

### _get_prog_args() of main_set_mode()
    if (&is_X) {
      if ( &_check_prog_on_list($prog_ref, $xlist) ) {
	$Viewer_Background = 1;
      } else {
	$Viewer_Background = 0;
	&_check_prog_on_list($prog_ref, $ttylist);
      }
    } else {			# is not X
      $Viewer_Background = 0;
      &_check_prog_on_list($prog_ref, $ttylist);
    }				# if is X
  } else {			# $opt is empty
    $Viewer_Background = 0;
    my $x;
    if (&is_X) {
      $x = &_get_first_prog($xlist);
      $Viewer_Background = 1 if $x;
    } else {			# is not X
      $x = &_get_first_prog($ttylist);
    }				# test on X
    $Display{'MODE'} = $mode if $x;
    return $x;
  }
  $Display{'MODE'} = $mode;
  return 1;
} # _get_prog_args() of main_set_mode()


##########
# _get_first_prog(<prog_list_ref>)
#
# Retrieve from the elements of the list in the argument the first
# existing program in $PATH.
#
# Local function of main_set_mode().
#
# Return  : `0' if not a part of the list, `1' if found in the list.
#
sub _get_first_prog {
  my $n = @_;
  die "_get_first_prog(): one argument is needed; you used $n;"
    unless $n == 1;

  foreach my $i (@{$_[0]}) {
    next unless $i;
    my %prog = &where_is_prog($i);
    if (%prog) {
      $Display{'PROG'} = $prog{'fullname'};
      $Display{'ARGS'} = $prog{'args'};
    }
    return 1;
  }
  return 0;
} # _get_first_prog() of main_set_mode()


##########
# _check_prog_on_list (<prog-hash-ref> <prog_list_ref>)
#
# Check whether the content of <prog-hash-ref> is in the list
# <prog_list_ref>.
# The globals are set correspondingly.
#
# Local function for main_set_mode().
#
# Arguments: 2
#
# Return  : `0' if not a part of the list, `1' if found in the list.
# Output  : none
#
# Globals in    : $Viewer_X{<MODE>}, $Viewer_tty{<MODE>}
# Globals in/out: $Display{'PROG'}, $Display{'ARGS'}
#
sub _check_prog_on_list {
  my $n = @_;
  die "_get_first_prog(): 2 arguments are needed; you used $n;"
    unless $n == 2;

  my %prog = %{$_[0]};

  $Display{'PROG'} = $prog{'fullname'};
  $Display{'ARGS'} = $prog{'args'};

  foreach my $i (@{$_[1]}) {
    my %p = &where_is_prog($i);
    next unless %p;
    next unless $Display{'PROG'} eq $p{'fullname'};
    if ($p{'args'}) {
      if ($Display{'ARGS'}) {
	$Display{'ARGS'} = $p{'args'};
      } else {
	$Display{'ARGS'} = "$p{'args'} $Display{'ARGS'}";
      }
    }				# if args
    return 1;
  }				# foreach $i
  # prog was not in the list
  return 0;
} # _check_prog_on_list() of main_set_mode()


########################################################################
# groffer temporary directory, main_temp()
########################################################################

sub main_temp {
  my $template = 'groffer_' . "$$" . '_XXXX';
  foreach ($ENV{'GROFF_TMPDIR'}, $ENV{'TMPDIR'}, $ENV{'TMP'}, $ENV{'TEMP'},
	   $ENV{'TEMPDIR'}, File::Spec->catfile($ENV{'HOME'}, 'tmp')) {
    if ($_ && -d $_ && -w $_) {
      if ($Debug{'KEEP'}) {
	eval { $tmpdir = tempdir( $template, DIR => "$_" ); };
      } else {
	eval { $tmpdir = tempdir( $template,
				  CLEANUP => 1, DIR => "$_" ); };
      }
      last if $tmpdir;
    }
  }
  $tmpdir = tempdir( $template, CLEANUP => 1, DIR => File::Spec->tmpdir )
    unless ($tmpdir);

  # see Lerning Perl, page 205, or Programming Perl, page 413
  # $SIG{'INT'} is for Ctrl-C interruption
  $SIG{'INT'} = sub { &clean_up(); die "interrupted..."; };
  $SIG{'QUIT'} = sub { &clean_up(); die "quit..."; };

  if ($Debug{'TMPDIR'}) {
    if ( $Debug{'KEEP'}) {
      print STDERR "temporary directory is kept: $tmpdir\n";
    } else {
      print STDERR "temporary directory will be cleaned: $tmpdir\n";
    }
  }

  # further argument: SUFFIX => '.sh'
  if ($Debug{'KEEP'}) {
    ($fh_cat, $tmp_cat) = tempfile(',cat_XXXX', DIR => $tmpdir);
    ($fh_stdin, $tmp_stdin) = tempfile(',stdin_XXXX', DIR => $tmpdir);
  } else {
    ($fh_cat, $tmp_cat) = tempfile(',cat_XXXX', UNLINK => 1,
				   DIR => $tmpdir);
    ($fh_stdin, $tmp_stdin) = tempfile(',stdin_XXXX', UNLINK => 1,
				       DIR => $tmpdir);
  }
}				# main_temp()


########################################################################
# tmp functions and compression
########################################################################

########################################################################
# further functions needed for main_do_fileargs()
########################################################################

my @REG_TITLE = ();

##########
# register_file(<filename>)
#
# Write a found file and register the title element.
#
# Arguments: 1: a file name
# Output: none
#
sub register_file {
  my $n = @_;
  die "register_file(): one argument is needed; you used $n;"
    unless $n == 1;
  die 'register_file(): file name is empty;' unless $_[0];

  if ($_[0] eq '-') {
    &to_tmp($tmp_stdin) && &register_title('stdin');
  } else {
    &to_tmp($_[0]) && &register_title($_[0]);
  }
  1;
}				# register_file()


##########
# register_title(<filespec>)
#
# Create title element from <filespec> and append to $_REG_TITLE_LIST.
# Basename is created.
#
# Globals in/out: @REG_TITLE
#
# Variable prefix: rt
#
sub register_title {
  my $n = @_;
  die "register_title(): one argument is needed; you used $n;"
    unless $n == 1;
  return 1 unless $_[0];

  return 1 if scalar @REG_TITLE > 3;

  my $title = &get_filename($_[0]);
  $title =~ s/\s/_/g;
  $title =~ s/\.bz2$//g;
  $title =~ s/\.gz$//g;
  $title =~ s/\.Z$//g;

  if ($Debug{'FILENAMES'}) {
    if ($_[0] eq 'stdin') {
      print STDERR "register_title(): file title is stdin\n";
    } else {
      print STDERR "register_title(): file title is $title\n";
    }
  }				# if ($Debug{'FILENAMES'})

  return 1 unless $title;
  push @REG_TITLE, $title;
  1;
}				# register_title()


##########
# save_stdin()
#
# Store standard input to temporary file (with decompression).
#
sub save_stdin {
  my ($fh_input, $tmp_input);
  $tmp_input = File::Spec->catfile($tmpdir, ',input');
  open $fh_input, ">$tmp_input" or
    die "save_stdin(): could not open $tmp_input";
  foreach (<STDIN>) {
    print $fh_input $_;
  }
  close $fh_input;
  open $fh_stdin, ">$tmp_stdin" or
    die "save_stdin(): could not open $tmp_stdin";
  foreach ( &cat_z("$tmp_input") ) {
    print $fh_stdin "$_";
  }
  close $fh_stdin;
  unlink $tmp_input unless $Debug{'KEEP'};
}				# save_stdin()


########################################################################
# main_do_fileargs()
########################################################################

sub main_do_fileargs {
  &special_setup();
  if ($Opt{'APROPOS'}) {
    if ($No_Filespecs) {
      &apropos_filespec();
      return 1;
    }
  } else {
    foreach (@Filespecs) {
      if (/^-$/) {
	&save_stdin();
	last;
      }
    }				# foreach (@Filespecs)
  }				# if ($Opt{'APROPOS'})

  my $section = '';
  my $ext = '';
  my $twoargs = 0;
  my $filespec;
  my $former_arg;

 FILESPEC: foreach (@Filespecs) {
    $filespec = $_;
    $Filespec_Arg = $_;
    $Filespec_Is_Man = 0;
    $Manspec = '';
    $Special_Filespec = 0;

    next FILESPEC unless $filespec;

### main_do_fileargs()
    if ($twoargs) {		# second run
      $twoargs = 0;
      # $section and $ext are kept from earlier run
      my $h = { 'name' => $filespec, 'sec' => $section, 'ext' => $ext };
      &man_setup();
      if ( &is_man($h) ) {
	$Filespec_Arg = "$former_arg $Filespec_Arg";
	&special_filespec();
	$Filespec_Is_Man = 1;
	&man_get($h);
	next FILESPEC;
      } else {
	warn "main_do_fileargs(): $former_arg is neither a file nor a " .
	  "man page nor a section argument for $filespec;";
      }
    }
    $twoargs = 0;

    if ( $Opt{'APROPOS'} ) {
      &apropos_filespec();
      next FILESPEC;
    }

    if ($filespec eq '-') {
      &register_file('-');
      &special_filespec();
      next FILESPEC;
    } elsif ( &get_filename($filespec) ne $filespec ) { # path with dir
      &special_filespec();
      if (-f $filespec && -r $filespec) {
	&register_file($filespec)
      } else {
	warn "main_do_fileargs: the argument $filespec is not a file;";
      }
      next FILESPEC;
    } else {			# neither `-' nor has dir
      # check whether filespec is an existing file
      unless ( $Man{'FORCE'} ) {
	if (-f $filespec && -r $filespec) {
	  &special_filespec();
	  &register_file($filespec);
	  next FILESPEC;
	}
      }
    }				# if ($filespec eq '-')

### main_do_fileargs()
    # now it must be a man page pattern

    if ($Macro_Pkg and $Macro_Pkg ne '-man') {
      warn "main_do_fileargs(): $filespec is not a file, " .
	"man pages are ignored due to $Macro_Pkg;";
      next FILESPEC;
    }

    # check for man page
    &man_setup();
    unless ( $Man{'ENABLE'} ) {
      warn "main_do_fileargs(): the argument $filespec is not a file;";
      next FILESPEC;
    }
    my $errmsg;
    if ( $Man{'FORCE'} ) {
      $errmsg = 'is not a man page';
    } else {
      $errmsg = 'is neither a file nor a man page';
    }

    $Filespec_Is_Man = 1;

### main_do_fileargs()
    # test filespec with `man:...' or `...(...)' on man page

    my @names = ($filespec);
    if ($filespec =~ /^man:(.*)$/) {
      push @names, $1;
    }

    foreach my $i (@names) {
      next unless $i;
      my $h = { 'name' => $i };
      if ( &is_man($h) ) {
	&special_filespec();
	&man_get($h);
	next FILESPEC;
      }
      if ( $i =~ /^(.*)\(([$Man{'AUTO_SEC_CHARS'}])(.*)\)$/ ) {
	$h = { 'name' => $1, 'sec' => $2, 'ext' => $3 };
	if ( &is_man($h) ) {
	  &special_filespec();
	  &man_get($h);
	  next FILESPEC;
	}
      }				# if //
      if ( $i =~ /^(.*)\.([$Man{'AUTO_SEC_CHARS'}])(.*)$/ ) {
	$h = { 'name' => $1, 'sec' => $2, 'ext' => $3 };
	if ( &is_man($h) ) {
	  &special_filespec();
	  &man_get($h);
	  next FILESPEC;
	}
      }				# if //
    }				# foreach (@names)

### main_do_fileargs()
    # check on "s name", where "s" is a section with or without an extension
    if ($filespec =~ /^([$Man{'AUTO_SEC_CHARS'}])(.*)$/) {
      unless ( $Man{'ENABLE'} ) {
	warn "main_do_fileargs(): $filespec $errmsg;";
	next FILESPEC;
      }
      $twoargs = 1;
      $section = $1;
      $ext = $2;
      $former_arg = $filespec;
      next FILESPEC;
    } else {
      warn "main_do_fileargs(): $filespec $errmsg;";
      next FILESPEC;
    }
  }				# foreach (@Filespecs)

  if ($twoargs) {
    warn "main_do_fileargs(): no filespec arguments left for second run;";
    return 0;
  }
  1;
} # main_do_fileargs()


########################################################################
# main_set_resources()
########################################################################

##########
# main_set_resources ()
#
# Determine options for setting X resources with $_DISPLAY_PROG.
#
# Globals: $Display{PROG}, $Output_File_Name
#
sub main_set_resources {
  # $prog   viewer program
  # $rl     resource list
  unlink $tmp_stdin unless $Debug{'KEEP'};
  $Output_File_Name = '';

  my @title = @REG_TITLE;
  @title = ($Opt{'TITLE'}) unless @title;
  @title = () unless @title;

  foreach my $n (@title) {
    next unless $n;
    $n =~ s/^,+// if $n =~ /^,/;
    next unless $n;
    $Output_File_Name = $Output_File_Name . ',' if $Output_File_Name;
    $Output_File_Name = "$Output_File_Name$n";
  }				# foreach (@title)

  $Output_File_Name =~ s/^,+//;
  $Output_File_Name = '-' unless $Output_File_Name;
  $Output_File_Name = File::Spec->catfile($tmpdir, $Output_File_Name);

### main_set_resources()
  unless ($Display{'PROG'}) {	# for example, for groff mode
    $Display{'ARGS'} = '';
    return 1;
  }

  my %h = &where_is_prog($Display{'PROG'});
  my $prog = $h{'file'};
  if ($Display{'ARGS'}) {
    $Display{'ARGS'} = "$h{'args'} $Display{'ARGS'}";
  } else {
    $Display{'ARGS'} = $h{'args'};
  }

  my @rl = ();

  if ($Opt{'BD'}) {
    if ($prog =~ /^(ghostview|gv|gxditview|xditview|xdvi)$/) {
      push @rl, '-bd', $Opt{'BD'};
    }
  }

  if ($Opt{'BG'}) {
    if ($prog =~ /^(ghostview|gv|gxditview|xditview|xdvi)$/) {
      push @rl, '-bg', $Opt{'BG'};
    } elsif ($prog eq 'kghostview') {
      push @rl, '--bg', $Opt{'BG'};
    } elsif ($prog eq 'xpdf') {
      push @rl, '-papercolor', $Opt{'BG'};
    }
  }

### main_set_resources()
  if ($Opt{'BW'}) {
    if ($prog =~ /^(ghostview|gv|gxditview|xditview|xdvi)$/) {
      push @rl, '-bw', $Opt{'BW'};
    }
  }

  if ($Opt{'FG'}) {
    if ($prog =~ /^(ghostview|gv|gxditview|xditview|xdvi)$/) {
      push @rl, '-fg', $Opt{'FG'};
    } elsif ($prog eq 'kghostview') {
      push @rl, '--fg', $Opt{'FG'};
    }
  }

  if ($Opt{'FN'}) {
    if ($prog =~ /^(ghostview|gv|gxditview|xditview|xdvi)$/) {
      push @rl, '-fn', $Opt{'FN'};
    } elsif ($prog eq 'kghostview') {
      push @rl, '--fn', $Opt{'FN'};
    }
  }

  if ($Opt{'GEOMETRY'}) {
    if ($prog =~ /^(ghostview|gv|gxditview|xditview|xdvi)$/) {
      push @rl, '-geometry', $Opt{'GEOMETRY'};
    } elsif ($prog eq 'kghostview') {
      push @rl, '--geometry', $Opt{'GEOMETRY'};
    }
  }

### main_set_resources()
  if ($Opt{'RESOLUTION'}) {
    if ($prog =~ /^(ghostview|gv|gxditview|xditview|xdvi)$/) {
      push @rl, '-resolution', $Opt{'RESOLUTION'};
    } elsif ($prog eq 'xpdf') {
      if ($Display{'PROG'} !~ / -z/) { # if xpdf does not have option -z
	if ($Default_Resolution == 75) {
	  push @rl, '-z', 104;
	} elsif ($Default_Resolution == 100) { # 72dpi is '100'
	  push @rl, '-z', 139;
	}
      }
    }				# if $prog
  } else {			# empty $Opt{RESOLUTION}
    $Opt{'RESOLUTION'} = $Default_Resolution;
    if ($prog =~ /^(gxditview|xditview)$/) {
      push @rl, '-resolution', $Default_Resolution;
    } elsif ($prog eq 'xpdf') {
      if ($Display{'PROG'} !~ / -z/) { # if xpdf does not have option -z
	if ($Default_Resolution == 75) {
	  push @rl, '-z', 104;
	} elsif ($Default_Resolution == 100) { # 72dpi is '100'
	  push @rl, '-z', 139;
	}
      }
    }				# if $prog
  }				# if $Opt{RESOLUTION}

  if ($Opt{'ICONIC'}) {
    if ($prog =~ /^(ghostview|gv|gxditview|xditview|xdvi)$/) {
      push @rl, '-iconic';
    }
  }

### main_set_resources()
  if ($Opt{'RV'}) {
    if ($prog =~ /^(ghostview|gv|gxditview|xditview|xdvi)$/) {
      push @rl, '-rv';
    }
  }

  if (@{$Opt{'XRM'}}) {
    if ($prog =~ /^(ghostview|gv|gxditview|xditview|xdvi|xpdf)$/) {
      foreach (@{$Opt{'XRM'}}) {
	push @rl, '-xrm', $_;
      }
    }
  }

  if (@title) {
    if ($prog =~ /^(gxditview|xditview)$/) {
      push @rl, '-title', $Output_File_Name;
    }
  }

  my $args = join ' ', @rl;
  if ($Display{'ARGS'}) {
    $Display{'ARGS'} = "$args $Display{'ARGS'}";
  } else {
    $Display{'ARGS'} = $args;
  }

  1;
}				# main_set_resources()


########################################################################
# set resources
########################################################################

my $groggy;
my $modefile;
my $addopts;

##########
# main_display ()
#
# Do the actual display of the whole thing.
#
# Globals:
#   in: $Display{MODE}, $Opt{DEVICE}, @Addopts_Groff,
#       $fh_cat, $tmp_cat, $Opt{PAGER}, $Output_File_Name
#
sub main_display {
  $addopts = join ' ', @Addopts_Groff;

  if (-z $tmp_cat) {
    warn "groffer: empty input\n";
    &clean_up();
    return 1;
  }

  $modefile = $Output_File_Name;

  # go to the temporary directory to be able to access internal data files
  chdir $tmpdir;

### main_display()
 SWITCH: foreach ($Display{'MODE'}) {
    /^groff$/ and do {
      push @Addopts_Groff, "-T$Opt{'DEVICE'}" if $Opt{'DEVICE'};
      $addopts = join ' ', @Addopts_Groff;
      $groggy = `cat $tmp_cat | grog`;
      die "main_display(): grog error;" if $?;
      chomp $groggy;
      print STDERR "grog output: $groggy\n" if $Debug{'GROG'};
      &_do_opt_V();
      unlink $modefile;
      rename $tmp_cat, $modefile;
      system("cat $modefile | $groggy $addopts");
      &clean_up();
      next SWITCH;
    };				# /groff/

    /^(text|tty)$/ and do {
      my $device;
      if (! $Opt{'DEVICE'}) {
	$device = $Opt{'TEXT_DEVICE'};
	$device = $Default_tty_Device unless $device;
      } elsif ($Opt{'DEVICE'} =~ /^(ascii||cp1047|latin1|utf8)$/) {
	$device = $Opt{'DEVICE'};
      } else {
	warn "main_display(): wrong device for $Display{'MODE'} mode: " .
	  "$Opt{'DEVICE'}";
      }
      $groggy = `cat $tmp_cat | grog -T$device`;
      die "main_display(): grog error;" if $?;
      chomp $groggy;
      print STDERR "grog output: $groggy\n" if $Debug{'GROG'};
      if ($Display{'MODE'} eq 'text') {
	&_do_opt_V();
	system("cat $tmp_cat | $groggy $addopts");
	&clean_up();
	next SWITCH;
      }

### main_display()
      # mode is not 'text', but `tty'
      my %pager;
      my @p;
      push @p, $Opt{'PAGER'} if $Opt{'PAGER'};
      push @p, $ENV{'PAGER'} if $ENV{'PAGER'};
      foreach (@p) {
	%pager = &where_is_prog($_);
	next unless %pager;
	if ($pager{'file'} eq 'less') {
	  if ($pager{'args'}) {
	    $pager{'args'} = "-r -R $pager{'args'}";
	  } else {
	    $pager{'args'} = '-r -R';
	  }
	}
	last if $pager{'file'};
      }				# foreach @p
      unless (%pager) {
	foreach (@{$Viewer_tty{'TTY'}}, @{$Viewer_X{'TTY'}}, 'cat') {
	  next unless $_;
	  %pager = &where_is_prog($_);
	  last if %pager;
	}
      }
      die "main_display(): no pager program found for tty mode;"
	unless %pager;
      &_do_opt_V();
      system("cat $tmp_cat | $groggy $addopts | " .
	     "$pager{'fullname'} $pager{'args'}");
      &clean_up();
      next SWITCH;
    };				# /text|tty/

    /^source$/ and do {
      open $fh_cat, "<$tmp_cat";
      foreach (<$fh_cat>) {
	print "$_";
      }
      &clean_up();
      next SWITCH;
    };

### main_display()
    /^dvi$/ and do {
      if ($Opt{'DEVICE'} && $Opt{'DEVICE'} ne 'dvi') {
	warn "main_display(): " .
	  "wrong device for $Display{'MODE'} mode: $Opt{'DEVICE'};"
      }
      $modefile .= '.dvi';
      $groggy = `cat $tmp_cat | grog -Tdvi`;
      die "main_display(): grog error;" if $?;
      chomp $groggy;
      print STDERR "grog output: $groggy\n" if $Debug{'GROG'};
      &_do_display();
      next SWITCH;
    };

    /^html$/ and do {
      if ($Opt{'DEVICE'} && $Opt{'DEVICE'} ne 'html') {
	warn "main_display(): " .
	  "wrong device for $Display{'MODE'} mode: $Opt{'DEVICE'};"
      }
      $modefile .= '.html';
      $groggy = `cat $tmp_cat | grog -Thtml`;
      die "main_display(): grog error;" if $?;
      chomp $groggy;
      print STDERR "grog output: $groggy\n" if $Debug{'GROG'};
      &_do_display();
      next SWITCH;
    };

    /^pdf$/ and do {
      if ($Opt{'DEVICE'} && $Opt{'DEVICE'} ne 'ps') {
	warn "main_display(): " .
	  "wrong device for $Display{'MODE'} mode: $Opt{'DEVICE'};"
      }
      $modefile .= '.ps';
      $groggy = `cat $tmp_cat | grog -Tps`;
      die "main_display(): grog error;" if $?;
      chomp $groggy;
      print STDERR "grog output: $groggy\n" if $Debug{'GROG'};
      &_do_display(\&_make_pdf);
      next SWITCH;
    };

### main_display()
    /^ps$/ and do {
      if ($Opt{'DEVICE'} && $Opt{'DEVICE'} ne 'ps') {
	warn "main_display(): " .
	  "wrong device for $Display{'MODE'} mode: $Opt{'DEVICE'};"
      }
      $modefile .= '.ps';
      $groggy = `cat $tmp_cat | grog -Tps`;
      die "main_display(): grog error;" if $?;
      chomp $groggy;
      print STDERR "grog output: $groggy\n" if $Debug{'GROG'};
      &_do_display();
      next SWITCH;
    };

    /^x$/ and do {
      my $device;
      if ($Opt{'DEVICE'} && $Opt{'DEVICE'} =~ /^X/) {
	$device = $Opt{'DEVICE'};
      } else {
	if ($Opt{'RESOLUTION'} == 100) {
	  if ( $Display{'PROG'} =~ /^(g|)xditview$/ ) {
	    # add width of 800dpi for resolution of 100dpi to the args
	    $Display{'ARGS'} .= ' -geometry 800';
	    $Display{'ARGS'} =~ s/^ //;
	  }
	} else {		# RESOLUTIOM != 100
	  $device = 'X75-12';
	}			# if RESOLUTIOM
      }				# if DEVICE
      $groggy = `cat $tmp_cat | grog -T$device -Z`;
      die "main_display(): grog error;" if $?;
      chomp $groggy;
      print STDERR "grog output: $groggy\n" if $Debug{'GROG'};
      &_do_display();
      next SWITCH;
    };

### main_display()
    /^X$/ and do {
      if (! $Opt{'DEVICE'}) {
	$groggy = `cat $tmp_cat | grog -X`;
	die "main_display(): grog error;" if $?;
	chomp $groggy;
	print STDERR "grog output: $groggy\n" if $Debug{'GROG'};
      } elsif ($Opt{'DEVICE'} =~ /^(X.*|dvi|html|lbp|lj4|ps)$/) {
	# these devices work with
	$groggy = `cat $tmp_cat | grog -T$Opt{'DEVICE'} -X`;
	die "main_display(): grog error;" if $?;
	chomp $groggy;
	print STDERR "grog output: $groggy\n" if $Debug{'GROG'};
      } else {
	warn "main_display(): wrong device for " .
	  "$Display{'MODE'} mode: $Opt{'DEVICE'};";
	$groggy = `cat $tmp_cat | grog -Z`;
	die "main_display(): grog error;" if $?;
	chomp $groggy;
	print STDERR "grog output: $groggy\n" if $Debug{'GROG'};
      }				# if DEVICE
      &_do_display();
      next SWITCH;
    };

    /^.*$/ and do {
      die "main_display(): unknown mode `$Display{'MODE'}';";
    };

  }				# SWITCH
  1;
} # main_display()


########################
# _do_display ([<prog>])
#
# Perform the generation of the output and view the result.  If an
# argument is given interpret it as a function name that is called in
# the midst (actually only for `pdf').
#
sub _do_display {
  &_do_opt_V();
  unless ($Display{'PROG'}) {
    system("$groggy $addopts $tmp_cat");
    &clean_up();
    return 1;
  }
  unlink $modefile;
  die "_do_display(): empty output;" if -z $tmp_cat;
  system("cat $tmp_cat | $groggy $addopts >$modefile");
  die "_do_display(): empty output;" if -z $modefile;
  &print_times("before display");
  if ($_[0] && ref($_[0]) eq 'CODE') {
    $_[0]->();
  }
  unlink $tmp_cat unless $Debug{'KEEP'};

  if ( $Opt{'STDOUT'} ) {
    my $fh;
    open $fh, "<$modefile";
    foreach (<$fh>) {
      print;
    }
    close $fh;
    return 1;
  }

  if ($Viewer_Background) {
    if ($Debug{'KEEP'}) {
      exec "$Display{'PROG'} $Display{'ARGS'} $modefile &";
    } else {
      exec "{ $Display{'PROG'} $Display{'ARGS'} $modefile; " .
	"rm -rf $tmpdir; } &";
    }
  } else {
    system("$Display{'PROG'} $Display{'ARGS'} $modefile");
    &clean_up();
  }
} # _do_display() of main_display()


#############
# _do_opt_V ()
#
# Check on option `-V'; if set print the corresponding output and leave.
#
# Globals: @ARGV, $Display{MODE}, $Display{PROG},
#          $Display{ARGS}, $groggy,  $modefile, $addopts
#
sub _do_opt_V {
  if ($Opt{'V'}) {
    $Opt{'V'} = 0;
    print "Parameters: @ARGV\n";
    print "Display Mode: $Display{'MODE'}\n";
    print "Output file: $modefile\n";
    print "Display prog: $Display{'PROG'} $Display{'ARGS'}\n";
    print "Output of grog: $groggy $addopts\n";
    my $res = `$groggy $addopts\n`;
    chomp $res;
    print "groff -V: $res\n";
    exit 0;
  }
  1;
} # _do_opt_V() of main_display()

##############
# _make_pdf ()
#
# Transform to pdf format; for pdf mode in _do_display().
#
# Globals: $md_modefile (from main_display())
#
sub _make_pdf {
  die "_make_pdf(): pdf mode did not work;" if $PDF_Did_Not_Work;
  my $psfile = $modefile;
  die "_make_pdf(): empty output;" if -z $modefile;
  $modefile =~ s/\.ps$/.pdf/;
  unlink $modefile;
  my $done;
  if ($PDF_Has_ps2pdf) {
    system("ps2pdf $psfile $modefile 2>$Dev_Null");
    $done = ! $?;
  }
  if (! $done && $PDF_Has_gs) {
    system("gs -q -dNOPAUSE -dBATCH -sDEVICE=pdfwrite " .
       "-sOutputFile=$modefile -c save pop -f $psfile 2>$Dev_Null");
    $done = ! $?;
  }
  if (! $done) {
    $PDF_Did_Not_Work = 1;
    warn '_make_pdf(): Could not transform into pdf format, ' .
      'the Postscript mode (ps) is used instead;';
    $Opt{'MODE'} = 'ps';
    &main_set_mode();
    &main_set_resources();
    &main_display();
    exit 0;
  }
  unlink $psfile unless $Debug{'KEEP'};
  1;
} # _make_pdf() of main_display()


########################################################################

&main_set_options();
&main_parse_MANOPT();
&main_config_params();
&main_parse_params();
&main_set_mode();
&main_temp();
&main_do_fileargs();
&main_set_resources();
&main_display();

&clean_up();

1;
########################################################################
### Emacs settings
# Local Variables:
# mode: CPerl
# End:

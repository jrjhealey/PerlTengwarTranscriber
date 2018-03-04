#!/usr/bin/perl

#    Perl Tengwar Transcriber. Converter from roman to tengwar and vice-versa
#    Copyright (C) 2006, Ignacio Fernández Galván (Jellby)
#                        jellby@yahoo.com
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

use strict;
use locale;
use Benchmark;

# "Global" variable declaration
my @r2t_pat;     #roman-to-tengwar patterns
my @r2t_index;   #index of roman-to-tengwar patterns
my $r2t;         #number of roman-to-tengwar patterns
my @t2r_pat;     #tengwar-to-roman patterns
my @t2r_index;   #index of tengwar-to-roman patterns
my $t2r;         #number of tengwar-to-roman patterns
my $cs;          #case sensitive mode
my @numbers;     #number patterns
my @modopt;      #mode file options
my $unknown;     #string for unknown transcriptions
my $transopts;   #transcription mode options

# The first argument is taken be the options block if it begins with a hyphen.
# Each option is assigned a value which is the number of times the
# corresponding letter appears in the options block, this is important for the
# $verbose option, which has different effects with different values.
#
# The mode file (the file containing the transcription rules) is the second
# argument, or the first one if it doesn't start with a hyphen. However, if the
# $transopts option was given, the second argument is the set of active mode
# options, and it must be a number, then the mode file is the third argument.

my $options = shift;
my ($help, $info, $out_only, $quiet, $verbose, $to_roman, $decimal, $no_reverse,
    $mode_file, $input_file , $output_file, %opts);
$transopts = "*"; #default value
if (substr($options,0,1) eq "-") {
  $options    =~ s/([^-])/$opts{$1}++;$1/eg;
  $help       = $opts{"h"}+$opts{"?"}; #write the usage help
  $info       = $opts{"m"}; #only process the mode file (don't transcribe)
  $out_only   = $opts{"o"}; #read from standard input, but output to a file
  $quiet      = $opts{"q"}; #do not print messages
  $verbose    = $opts{"v"}; #write info about the mode file
  $to_roman   = $opts{"r"}; #tengwar-to-roman transcription
  $decimal    = $opts{"d"}; #write decimal numbers
  $no_reverse = $opts{"n"}; #write left-to-right numbers
  if ($opts{"p"}) {         #transcription mode options
    # Read the next argument and check whether it is a number.
    $transopts = shift;
    $help = 1 if ($transopts !~ /^(([+-]\d+)+|\d+)$/);
  }
  $mode_file = shift;
} else {
  $mode_file = $options;
}

# If no mode file was given in the input, or if help was asked for, a short
# usage summary is printed.

$help = 1 if ($mode_file eq "");
unless ($quiet) {
  print "\n".<<EOF;
******** Perl Tengwar Transcriber v1.2, ©2006 Jellby *********
* This program comes with ABSOLUTELY NO WARRANTY.            *
* This is free software, and you are welcome to redistribute *
* it under certain conditions. See the included file COPYING *
* for details.                                               *
**************************************************************
EOF
}
if ($help) {
  warn <<EOF;
Usage:	$0 [-options] [mode-opts] mode-file [in-file] [out-file]

Options:
	h, ?	This help
	m	Process the mode file only (no transcription)
	o	Use the standard input as input-file (useful for pipes)
	q	Quiet mode, do not print any message
	v	Be verbose about the mode file
	vv	Be more verbose
	r	Reverse transcription (tengwar to roman)
	d	Write numbers in decimal base
	n	Write numbers in left-to-right order
	p	Supply transcription mode options before mode-file
Default is roman to tengwar and duodecimal, right-to-left numbers.
Transcription mode options are built into each mode file,
use "$0 -mv mode.ptm" to see them if they are available.

Examples:
	$0 -vd mymode.ptm input.txt output.tng
	$0 -oqp +4-7 othermode.ptm output.tng < input.txt
EOF
  exit;
}

# Read the mode file.

open(MODE, "<$mode_file") || die("Could not open mode file \"$mode_file\"\n");
my @raw_mode = <MODE>;
close(MODE);
&read_mode(\@raw_mode);

# The transcription is only attempted is the -m option wasn't given.

unless ($info) {

  # Read the input either from the input file or from the standard input if no
  # input file was given.

  $input_file = shift unless ($out_only);
  my @read;
  if ($input_file eq "") {
    print "\nWrite your text:\n\n" unless ($quiet);
    open(INPUT, "<-");
    @read = <INPUT>;
  } else {
    open(INPUT, "<$input_file") ||
      die("Could not open input file \"$input_file\"\n");
    @read = <INPUT>;
    print "\nInput read from file \"$input_file\"\n" unless($quiet);
  }
  close(INPUT);

  # Open the output file for writing.
  # If no output file was given, create an "alias" for the standard output.

  $output_file = shift;
  if ($output_file ne "") {
    open(OUTPUT, ">$output_file") ||
      die("Could not open output file \"$output_file\"\n");
  } else {
    open(OUTPUT, ">-");
    print "\nTranscribed text:\n".
          "==========================\n\n" unless($quiet);
  }

  # Set the default "unknown" string, for when a character has unknown
  # transcription.

  $unknown = "¬";

  # Process the input line by line with the appropriate subroutine and write the
  # output. Time it too

  my $start_time = new Benchmark; #store start time
  my $trans;
  for my $line (@read) {
    if ($to_roman) {
      $trans = &transcribe2roman($line);
    } else {
      $trans = &transcribe2tengwar($line);
    }
    print OUTPUT $trans;
  }
  my $end_time = new Benchmark; #store end time
  &timestr(&timediff($end_time, $start_time),"noc") =~/=([\d. ]*)/;
  my $time = $1+0;

  # Finish up.

  print "Output written to file \"$output_file\"\n"
    unless ($output_file eq "" || $quiet);
  printf "\nTime spent: %5.2f seconds\n", $time unless($quiet);

  close(OUTPUT);
}

print "\n" unless ($quiet);

exit;

#===============================================================================
# Subroutines
#===============================================================================

#===============================================================================
# Removes blank characters (spaces, tabs...) from both ends of a string.
sub trim {
  my $string = shift;
  $string =~ s/^\s+//; #remove blanks from the beginning
  $string =~ s/\s+$//; #remove blanks from the end
  return $string;
}

#===============================================================================
# Stop with a wrong mode file.
sub wrong_format {
  die("Error: Wrong mode file format\n");
}

#===============================================================================
# Print a warning if the number of patterns in the mode file does not agree
# with the number stated in its header.
sub pattern_warning {
  my $a = shift;
  my $b = shift;
  warn "Warning: Number of patterns does not match ($a vs $b)\n"
}

#===============================================================================
# Read the mode file.
sub read_mode {
  my $file = shift;
  &read_header(\@$file); #read the header first
  &read_patterns(\@$file); #read the pattern
  @r2t_index = &sort_patterns(@r2t_pat); #|
  @t2r_index = &sort_patterns(@t2r_pat); #|sort the patterns
  &write_summary(); #write a summary if necessary
}

#===============================================================================
# Read the header of the mode file. Also check it's a mode file with the
# correct format (Perl Tengwar Mode File).
sub read_header {
  my $file = shift;
  my ($line, $field1, $field2);

  # Read the first line, it must have the following format:
  #   ["#<Perl-TMF>"] [tab] [arbitrary comment]
  # The comment is used only as a caption in the screen.
  $line = shift(@$file);
  ($field1, $field2) = split(/\t/, $line);
  &wrong_format() if (&trim($field1) ne "#<Perl-TMF>");
  print "Using mode:\t".&trim($field2)."\n" unless($quiet);

  # Read the 2nd, 3rd and 4th lines, which must have these formats:
  #   ["#r2t"] [tab] [number of roman-to-tengwar patterns]
  #   ["#t2r"] [tab] [number of tengwar-to-roman patterns]
  #   ["#cs"]  [tab] [0/1 indicating the case-sensitivity of the mode]
  # (the case-sensitivity affects only the roman-to-tengwar transcription).
  $line = shift(@$file);
  ($field1, $field2) = split(/\t/, $line);
  &wrong_format() if (&trim($field1) ne "#r2t");
  $r2t = &trim($field2)+0; #add 0 to get a pure number
  $line = shift(@$file);
  ($field1, $field2) = split(/\t/, $line);
  &wrong_format() if (&trim($field1) ne "#t2r");
  $t2r = &trim($field2)+0; #add 0 to get a pure number
  $line = shift(@$file);
  ($field1, $field2) = split(/\t/, $line);
  &wrong_format() if (&trim($field1) ne "#cs");
  $cs = &trim($field2)+0; #add 0 to get a pure number

  # Read the 5th line, if it contains:
  #   ["#OPTIONS:"]
  # then read the options for the mode. Otherwise go on.
  $line = shift(@$file);
  if (&trim($line) eq "#OPTIONS:") {
    $line = &read_options(\@$file);
  }

  # Check the final line of the header, which must be exactly:
  #   ["#pat"] [tab] ["conv"] [tab] ["next"] [tab] ["prev"]
  &wrong_format() if (&trim($line) ne "#pat\tconv\tnext\tprev");
}

#===============================================================================
# Reads the transcription options built into the mode file and sets them to the
# default values or to the ones given it the command line
sub read_options {
  my $file = shift;
  my ($line, $a, $b, $num, $desc);

  # Read each line and consider it an option if it fits into the pattern:
  #   ["#"] [num] [["*"]] [tab] [[comment]]
  # The optional * marks the options turned on by default.
  $line = shift(@$file);
  while ($line =~ /^#\d+\*?\t/) {
    ($a, $b) = split(/\t/, &trim($line));
    ($num) = ($a =~ /^#(\d+)/); #extract the number of the option
    $num--;
    $modopt[$num][0] = ($a =~ /\*/) + 0; #set it to 1 if there is a *
    $modopt[$num][1] = $modopt[$num][0];
    $modopt[$num][2] = $b;
    $line = shift(@$file);
  }

  # Set the option given in the command line.
  if ($transopts ne "*") {
    if ($transopts =~ /^[+-]/) {
      # If the command line is a series of +/-num tags, set the state of the
      # corresponding options, starting from the default.
      while ($transopts =~ /([+-])(\d+)/g) {
        $modopt[$2-1][1] = $1 eq "+" ? 1 : 0; # sign + means 1, sign - means 0
      }
    } else {
      # If a simple number, it's read as a binary chain of states: option $i is
      # turned on if bit $i is 1, turned off otherwise.
      $b = $transopts;
      for my $i (0 .. $#modopt) {
        $a = $b % 2;
        $b = $b / 2;
        $modopt[$i][1] = $a; #set the option to the remainder of division by 2
      }
    }
  }

  return $line;
}

#===============================================================================
# Check whether a pattern is active, matching the options of the pattern and the
# current transcription options.
sub active {
  my $opt = shift;
  my $res = 1;
  my $sign;

  # Split the pattern options chunk in +/-num tags. For each tag, check option
  # $num-1 and deactivate the pattern if the state of the option doesn't math
  # with the sign in the tag.
  while ($opt =~ /([+-])(\d+)/g) {
    $sign = $1 eq "+" ? 1 : 0; #sign + means 1, sign - means 0
    if ($modopt[$2-1][1] != $sign) {
      $res = 0;
      last;
    }
  }

  return $res;
}

#===============================================================================
# Sort a pattern array by the first letter, keeping the relative order. This
# should be safe and help to optimise the search.
sub sort_patterns {
  my @pat = @_;
  my (@aux, @ordindex);
  my $l = 0;

  # For each character code, look for patterns starting with that character.
  for my $i (0 .. 255) {
    for my $j ($l .. $#pat) {
      if (ord($pat[$j][0]) == $i) {
        # Update the ordindex matrix to hold where to find each pattern.
        $ordindex[$i][0] = $l if ($ordindex[$i][0] eq "");
        $ordindex[$i][1] = $l;
        # Once a match is found, move this pattern to the current place (kept
        # in $l), pushing all intermediate patterns down the list.
        @aux = @{$pat[$j]};
        for my $k (reverse $l+1 .. $j) {
          @{$pat[$k]} = @{$pat[$k-1]};
        }
        @{$pat[$l]} = @aux;
        $l++; #one more pattern has been ordered
      }
    }
  }

  return @ordindex;
}

#===============================================================================
# Read the different patterns in the mode file with some checks.
# There are three kinds of pattern: roman-to-tengwar, tengwar-to-roman, and
# numbers; the different kinds are separated by lines containing "#==="
# and there's a special header line before the number patterns, although the
# number patterns are optional.
sub read_patterns {
  my $file = shift;
  my ($line, $i, $opt);

  # Read first roman-to-tengwar and then tengwar-to-roman patterns.
  # Each pattern has the format:
  #   [pat] [tab] [[conv]] [tab] [[next]] [tab] [[prev]] [[tab] [opts]]
  # where the "conv", "next" and "prev" parts are optional, but not the tabs.
  # Lines with empty "pat" (lines beginning with a tab) are ignored, so they
  # can be use to keep comments or to disable patterns. A pattern may end with
  # an options chunk which tells in which cases should the pattern be active.
  for ($i=0; ; $i++) {
    &wrong_format() if (@$file == 0); #stop if file ends unexpectedly
    $line = shift(@$file);
    chop($line);
    last if (&trim($line) eq "#==="); #end of roman-to-tengwar patterns
    redo if ($line =~ /^\t/); #ignored line
    &wrong_format() if ($line !~ /^([^\t]+\t[^\t]*\t[^\t]*\t[^\t]*)(\t([+-]\d+)+)?$/);
    ($line, $opt) = ($1, &trim($2)); #split true pattern and options
    if (&active($opt)) { #ignore pattern if it's not active
      push @r2t_pat, [ split(/\t/, $line) ]; #store pattern
      $r2t_pat[$#r2t_pat][0] = lc($r2t_pat[$#r2t_pat][0]) unless ($cs);
    }
  }
  &pattern_warning($i, $r2t) if ($i != $r2t);
  $r2t = $i; #store number of roman-to-tengwar patterns

  # Now tengwar-to-roman patterns.
  for ($i=0; ; $i++) {
    &wrong_format() if (@$file == 0); #stop if file ends unexpectedly
    $line = shift(@$file);
    chop($line);
    last if (&trim($line) eq "#==="); #end of tengwar-to-roman patterns
    redo if ($line =~ /^\t/); #ignored line
    &wrong_format() if ($line !~ /^([^\t]+\t[^\t]*\t[^\t]*\t[^\t]*)(\t([+-]\d+)+)?$/);
    ($line, $opt) = ($1, &trim($2)); #split true pattern and options
    if (&active($opt)) { #ignore pattern if it's not active
      push @t2r_pat, [ split(/\t/, $line) ]; #store pattern
    }
  }
  &pattern_warning($i, $t2r) if ($i != $t2r);
  $t2r = $i; #store number of tengwar-to-roman patterns

  # The number patterns, if present, must start with the header line:
  #   ["#digit"] [tab] ["dec"] [tab] ["duodec"] [tab] ["least"]
  # there must be exactly 12 patterns with the format:
  #   [dig] [tab] [dec] [tab] [duodec] [tab] [least]
  # where "dig" are the numbers 0 .. 12.
  $line = shift(@$file);
  unless (@$file == 0 || $line eq "") {
    &wrong_format() if (&trim($line) ne "#digit\tdec\tduodec\tleast");
    for my $k (0 .. 11) {
      &wrong_format() if (@$file == 0); #stop if file ends unexpectedly
      $line = shift(@$file);
      chop($line);
      &wrong_format() if ($line !~ /^[^\t]+\t[^\t]*\t[^\t]+\t[^\t]+$/);
      push @numbers, [ split(/\t/, $line) ]; #store pattern
      &wrong_format() if ($numbers[$k][0] != $k);
    }
  }
}

#===============================================================================
# Write a summary of the mode file if requested.
sub write_summary {
  # For low verbosity, just some data.
  if ($verbose >= 1) {
    my $mycs = ($cs==1)?"Yes":"No";
    my $mynum = ($#numbers==11)?"Yes":"No";
    print "==========================\n".
          "Roman to tengwar patterns:\t$r2t\n".
          "Tengwar to roman patterns:\t$t2r\n".
          "Case-sensitive mode:\t\t$mycs\n".
          "Number patterns included:\t$mynum\n".
          "==========================\n";
    if ($#modopt >= 0) {
      print "Mode options:\n";
      print "(def)\t\(sel)\tadd\tdescription\n";
      my ($def, $sel) = (0, 0);
      for my $i (0 .. $#modopt) {
        if ($modopt[$i][0]) {
          $def += 2**$i;
          print "+".($i+1)."\t";
        } else {
          print "-".($i+1)."\t";
        }
        if ($modopt[$i][1]) {
          $sel += 2**$i;
          print "  *\t";
        } else {
          print "   \t";
        }
        print "(".2**$i.")\t";
        print "$modopt[$i][2]\n";
      }
      print "----------------\n";
      print "Selected:\t$sel\n" if ($transopts ne "*");
      print "Default:\t$def\n".
            "==========================\n";
    }
  }

  # For high verbosity, write also all the patterns found in the mode.
  if ($verbose >= 2) {
    print "Roman to tengwar patterns:\n";
    for my $k (0 .. $#r2t_pat) {
      printf "[%03u]\t%s\t%s\t%s\t%s\n", $k+1, @{$r2t_pat[$k]};
    }
    print "Tengwar to roman patterns:\n";
    for my $k (0 .. $#t2r_pat) {
      printf "[%03u]\t%s\t%s\t%s\t%s\n", $k+1, @{$t2r_pat[$k]};
    }
    # Write the number patterns only if present.
    if ($#numbers == 11) {
      print "Number patterns:\n";
      for my $k (0 .. 11) {
        printf "[%03u]\t%s\t%s\t%s\t%s\n", $k, @{$numbers[$k]};
      }
    }
    print "==========================\n";
  }
}

#===============================================================================
# Check $string to see if it matches the pattern $pat.
# Return the length of the match or 0.
sub check_pattern {
  my $string = shift;
  my $pat = shift;
  my $len = length($pat);
  $len = 0 unless (substr($string,0,$len) eq $pat);
  return $len;
}

#===============================================================================
# Attach $dig to $num, to the left or to the right depending on the value of
# $no_reverse (global option). Digits are added least-significant first.
sub add_digit {
  my $num = shift;
  my $dig = shift;
  $no_reverse ? ($$num=$dig.$$num) : ($$num=$$num.$dig);
}

#===============================================================================
# Find whether there is a tengwar digit (and which one) of the appropriate
# $kind at the beginning of $string. $kind is 1 for decimal, 2 for duodecimal,
# and 3 for least-significant duodecimal.
# Return the digit value and the length of the tengwar string.
sub find_digit {
  my $string = shift;
  my $kind = shift;
  my ($len, $dig);

  # Loop over all digits of the kind and test for a match
  # If a match is found, set $dig accordingly.
  $dig = "";
  for my $k (0 .. 11) {
    last if ($kind == 1 && $k > 9); #skip 10 and 11 if decimal
    $len = &check_pattern($string, $numbers[$k][$kind]);
    next if ($len == 0); #try a different digit if there isn't a match
    $dig = $k;
    last;
  }

  return ($dig, $len);
}

#===============================================================================
# Do the main transcription from roman to tengwar, the line to transcribe is
# the input, return the transcribed line.
sub transcribe2tengwar {
  my $line = shift;
  my $trans = "";
  my ($test, $len, $done, $num, $i);

  # Convert to lowercase if needed.
  # Add spaces at the beginning and at the end to allow end-of-word matching,
  # and substitute all blanks with spaces.
  $line = lc($line) unless $cs;
  $line =~ s/[\r\n]//g;
  $line =~ s/\s/ /g;
  $line = " " . $line . " ";

  # Return if the line is empty (to avoid having spurious spaces)
  return "\n" if ($line =~ /^\s*$/);

  # $i is a counter marking the length of the line already transcribed,
  # $test is the rest of the line, yet to be transcribed.
  # The loop is repeated until there is nothing more to transcribe
  $i = 1;
  $test = substr($line,$i);
  until (length($test) <= 1) {
    $done = 0;
    # Do not change tabs
    if (substr($test,$i,1) eq "\t") {
      $trans .= "\t";
      $i++;
      $test = substr($test,1);
      next;
    }
    # Check only roman-to-tengwar patterns starting with the same character, if
    # any. If a match is found, check the preceding and following strings,
    # treated as regular expressions.
    $num = ord($test);
    if ($r2t_index[$num][0] ne "") {
      for my $k ($r2t_index[$num][0] .. $r2t_index[$num][1]) {
        $len = &check_pattern($test, $r2t_pat[$k][0]);
        next if ($len == 0); #try next pattern if no match
        if (substr($line,0,$i) =~ /$r2t_pat[$k][3]$/ &&
            substr($test,$len) =~ /^$r2t_pat[$k][2]/) {
          $trans .= $r2t_pat[$k][1]; #add the transcribed string
          $i += $len;                 #|
          $test = substr($test,$len); #|update counter and test string
          $done = 1;
          last;
        }
      }
    }
    # If no pattern matches, try with a number (if there are number patterns).
    next if ($done);
    if ($#numbers == 11) {
      ($num, $len) = &transcribe_number($test);
      if ($len > 0) { #if a number is found
        $trans .= $num;
        $i += $len;
        $test = substr($test,$len);
        $done = 1;
      }
    }
    # If there's no number either, add a default "unknown" string and advance
    # one character.
    next if ($done);
    $trans .= $unknown;
    $i++;
    $test = substr($test,1);
  }

  return $trans."\n";
}

#===============================================================================
# Do the main transcription from tengwar to roman, the line to transcribe is
# the input, return the transcribed line.
sub transcribe2roman {
  my $line = shift;
  my $trans = "";
  my ($test, $len, $done, $num, $i);

  # Add spaces at the beginning and at the end to allow end-of-word matching,
  # and substitute all blanks with spaces.
  $line =~ s/[\r\n]//g;
  $line =~ s/\s/ /g;
  $line = " " . $line . " ";

  # $i is a counter marking the length of the line already transcribed,
  # $test is the rest of the line, yet to be transcribed.
  # The loop is repeated until there is nothing more to transcribe (just the
  # last space).
  $i = 1;
  $test = substr($line,$i);
  until (length($test) <= 1) {
    $done = 0;
    # Check only tengwar-to-roman patterns starting with the same character, if
    # any. If a match is found, check the preceding and following strings,
    # treated as regular expressions.
    $num = ord($test);
    if ($t2r_index[$num][0] ne "") {
      for my $k ($t2r_index[$num][0] .. $t2r_index[$num][1]) {
        $len = &check_pattern($test, $t2r_pat[$k][0]);
        next if ($len == 0); #try next pattern if no match
        if (substr($line,0,$i) =~ /$t2r_pat[$k][3]$/ &&
            substr($test,$len) =~ /^$t2r_pat[$k][2]/) {
          $trans .= $t2r_pat[$k][1]; #add the transcribed string
          $i += $len;                 #|
          $test = substr($test,$len); #|update counter and test string
          $done = 1;
          last;
        }
      }
    }
    # If no pattern matches, try with a number (if there are number patterns).
    next if ($done);
    if ($#numbers == 11) {
      ($num, $len) = &decode_number($test);
      if ($len > 0) { #if a number is found
        $trans .= $num;
        $i += $len;
        $test = substr($test,$len);
        $done = 1;
      }
    }
    # If there's no number either, add a default "unknown" string and advance
    # one character.
    next if ($done);
    $trans .= $unknown;
    $i++;
    $test = substr($test,1);
  }

  return $trans."\n";
}

#===============================================================================
# Transcribe number from decimal arabic to tengwar.
sub transcribe_number {
  use integer; #use integer arithmetic
  my $string = shift;
  my $res = "";
  my ($num, $len, $dig, $least);

  # Find which arabic numbers are in the string to transcribe.
  ($num) = ($string =~ /(^\d+)/);
  $len = length($num);

  # Both decimal and duodecimal transcriptions are made my joining the
  # successive remainders of the division by 10 or 12. For duodecimal
  # transcription, the least significant digit (first remainder) is marked,
  # something that's currently not done for decimal transcription.
  if ($len == 0) {
    # No number found, do nothing.
  } elsif ($decimal) {
    &add_digit(\$res, $numbers[0][1]) if ($num == 0); #special case for 0
    $least = 1;
    while ($num > 0) {
      $dig = $num % 10; #get remainder of division by 10
      &add_digit(\$res, $numbers[$dig][1]);
      $num = $num/10; #integer division by 10
      $least = 0;
    }
  } else {
    &add_digit(\$res, $numbers[0][2]) if ($num == 0); #special case for 0
    $least = 1;
    while ($num > 0) {
      $dig = $num % 12; #get remainder of division by 12
      if ($least && $num >= 12) {
        &add_digit(\$res, $numbers[$dig][3]);
      } else {
        &add_digit(\$res, $numbers[$dig][2]);
      }
      $num = $num/12; #integer division by 12
      $least = 0;
    }
  }

  return ($res, $len);
}

#===============================================================================
# Convert a number from tengwar back to decimal arabic.
# Return the converted number and the length of the tengwar string.
sub decode_number {
  my $string = shift,
  my ($len, $dig);

  # Find out whether there is a number in the string as well as its kind.
  my ($kind, $num, $disp, $exp) = (0, 0, 0, 0);
  for my $k (1 .. 3) {
    ($dig, $len) = &find_digit($string, $k);
    next if ($len == 0);
    $kind = $k;
    last;
  }

  if ($kind == 0) {
    # No number found, do nothing.
  } elsif ($kind == 1) {
    # Search decimal digits and build the number. Stop when no more decimal
    # digits are found.
    # Note that there is no mark in the least significant digit, so the
    # direction of the number is given by the $no_reverse global option.
    do {
      ($dig, $len) = &find_digit($string, 1);
      last if ($len == 0); #stop if no digit found
      if ($no_reverse) {
        $num *= 10;   #|
        $num += $dig; #|add most significant first
      } else {
        $num += $dig*10**$exp; #|
        $exp++;                #|add least significant first
      }
      $disp += $len;
      $string = substr($string,$len);
    };
  } elsif ($kind == 2) {
    # Search duodecimal digits, when no more are found, look for a possible
    # digit marked as least significant. Add the numbers most significant first
    # in any case.
    do {
      ($dig, $len) = &find_digit($string, 2);
      last if ($len == 0); #stop if no digit found
      $num *= 12;
      $num += $dig;
      $disp += $len;
      $string = substr($string,$len);
    };
    ($dig, $len) = &find_digit($string, 3);
    if ($len > 0) { #add the least significant digit if it's marked as such
      $num *= 12;
      $num += $dig;
      $disp += $len;
      $string = substr($string,$len);
    }
  } elsif ($kind == 3) {
    # After taking the least significant digit, search for more duodecimal
    # digits. Stop when no more digits are found.
    $num += $dig;
    $exp++;
    $disp += $len;
    $string = substr($string,$len);
    do {
      ($dig, $len) = &find_digit($string, 2);
      last if ($len == 0); #stop if no digit found
      $num += $dig*12**$exp;
      $exp++;
      $disp += $len;
      $string = substr($string,$len);
    };
  }

  return ($num, $disp);
}

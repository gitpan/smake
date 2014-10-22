#!@PATH_PERL@
eval 'exec @PATH_PERL@ -S $0 ${1+"$@"}'
    if $running_under_some_shell;
##   ____ __  __       _        
##  / ___|  \/  | __ _| | _____ 
##  \___ \ |\/| |/ _` | |/ / _ \
##   ___) ||  | | (_| |   <  __/
##  |____/_|  |_|\__,_|_|\_\___|
##                             
##  SMake -- Makefile generator
##
##  SMake is a powerful mechanism to generate standard Makefiles out
##  of skeleton Makefiles which only provide the essential parts.
##  The missing stuff gets automatically filled in by shared include
##  files. A great scheme to create a huge Makefile hierarchy and to
##  keep it consistent for the time of development.  The trick is
##  that it merges the skeleton and the templates in a
##  priority-driven way. The idea is taken from X Consortiums Imake,
##  but the goal here is not inherited system independency, the goal
##  is consistency and power without the need of manually maintaining
##  a Makefile hierarchy. 
##
##  Copyright (C) 1994-1997 Ralf S. Engelschall, <rse@engelschall.com>
##
##  This program is free software; it may be redistributed and/or
##  modified only under the terms of the GNU General Public License,
##  which may be found in the SMake source distribution.  Look at the
##  file COPYING. 
##  
##  This program is distributed in the hope that it will be useful,
##  but WITHOUT ANY WARRANTY; without even the implied warranty of
##  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
##  General Public License for more details.
## 
##  smake_smake.pl -- main procedure for "smake" executable
##

require 5.0;

#   include the common parts
#   (these will be substituted by 
#    the real contents via ``unrequire'' later)
require "smake_misc.pl";
require "smake_getopts.pl";
require "smake_file.pl";
require "smake_vers.pl";

#
#   print command line usage
#
sub usage {
print <<'EOT';
Usage: smake [options] inputfile
  were options are
    -o outputfile    write result to outputfile instead of `Makefile'
    -I includepath   add includepath to list of include directories
    -x               debug mode
    -V               display version identification string
    -h               display usage list (this one)
EOT
}

#
#   parse arguments into our internal variables
#
if (&Getopts('o:I+xVh') == 0) {
    &usage;
    exit $EX{'USAGE'};
}
if ($opt_h) {
    &usage;
    exit $EX{'OK'};
}
if ($opt_V) {
    print "$SMake_Hello\n";
    exit $EX{'OK'};
}
if ($#ARGV eq -1) {
    $inputfile = "SMakefile";
}
elsif ($#ARGV eq 0) {
    $inputfile = @ARGV[0];
}
else {
    &usage;
    exit $EX{'USAGE'};
}
$outputfile  = $opt_o ne '' ? $opt_o : 'Makefile';
@includepath = ();
if ($#opt_I != -1) {
    push(@includepath, @opt_I);
}
push(@includepath, split(':', $default_includepath));
$includepath = join(':', @includepath);
$debug = $opt_x ? 1 : 0;


#
#   get additional options from .opt line of inputfile
#
open(FPI, "<$inputfile");
$options = "";
while (<FPI>) {
    if (m|^\.opt (.*)|) {
        $options .= $1;
    }
}
close(FPI);
@ARGV = split(/ /, $options);
if (&Getopts('o:I+xVh') == 0) {
    print "Bad .opt line\n";
    exit $EX{'USAGE'};
}
$outputfile = $opt_o ne '' ? $opt_o : $outputfile;
if ($#opt_I != -1) {
    $includepath .= ":" . join(':', @opt_I);
}
$debug = $opt_x ? 1 : $debug;


#
#   Initialize the statistic variables
#
$stat_sourcelines        = 0;
$stat_includedfiles      = 0;
$stat_includedlines      = 0;
$stat_removeddefinelines = 0;
$stat_removeddefines     = 0;
$stat_removedtargetlines = 0;
$stat_removedtargets     = 0;
$stat_removedopt         = 0;
$stat_removedpri         = 0;

#
#   PASS 1: process inputfile and expand .include statements
#
$tmpfile = "$tmpdir/tmp.$prgname.$$.$inputfile";
open(INPUT,  "<$inputfile");
open(OUTPUT, ">$tmpfile");
$line = 0;
while (<INPUT>) {
    $line++;
    $stat_sourcelines++;

    if (m|^\.include[ \t]*<(.*)>[ \t]*$|) {
        $includefile=$1;

        #   search for include file in include path
        #   and if found read the file
        $found = 0;
        foreach $dir (split(/:/, $includepath)) {
            if (-r "$dir/$includefile") {
                $found = 1;
                open(INCLUDE, "<$dir/$includefile");
                while (<INCLUDE>) {
                    print OUTPUT "$_";
                    $stat_includedlines++;
                }
                close(INCLUDE);
                $stat_includedfiles++;
                last;
            }
        }
        print "'$inputfile', line $line: file '$includefile' not found in $includepath\n" if ($found eq 0); 
    }

    elsif (m|^\.include[ \t]*\"(.*)\"[ \t]*$|) {
        $includefile=$1;

        #    if include file exists read it
        if (-r "$includefile") {
            open(INCLUDE, "<$includefile");
            while (<INCLUDE>) {
                print OUTPUT "$_";
            }
            close(INCLUDE);
            $stat_includedfiles++;
            last;
        }
        else {
            print "'$inputfile', line $line: file '$includefile' not found\n";
        }
    }

    elsif (m|^\.opt.*|) {
        #    ignore any .opt line (they were used prior)
        $stat_removedopt++;
        next;
    }

    else {
        #    any other lines are verbatim copied to the output file
        print OUTPUT $_;
    }
}
close(OUTPUT);
close(INPUT);


#
#   PASS 2: strip double-defined targets and definitions
#
$priority     = 0;
%define_pri   = ();
%define_lines = ();
%target_pri   = ();
%target_lines = ();
%verbatim     = ();
@outputlines  = ();
$linenoFirst  = 0;
$linenoCur    = 0;

sub setOutput {
   my ($first, $last, $what) = @_;

   while ($first <= $last) {
       $outputlines[$first] = $what;
       $first++;
   }
}

sub setPri {
    my ($lineno, $pri) = @_;

    if ($pri =~ m|[+-]\d+|) {
        $priority = $priority + $pri;
    }
    else {
        $priority = $pri;
    }
    print "    => Priority: <$priority>\n" if $debug;
    print "    => $lineno: remove\n" if $debug;
    &setOutput($lineno, $lineno, 'remove');
    $stat_removedpri++;
}

sub setDefine {
    my ($linenoFirst, $linenoLast, $key) = @_;

    if ($define_pri{$key} ne '') {
        if ($define_pri{$key} <= $priority) {

            #   remove output of old one
            ($first, $last) = split(/:/, $define_lines{$key});
            &setOutput($first, $last, 'remove');
            print "    => $first - $last: remove DEFINE\n" if $debug;
            $stat_removeddefines++;
            $stat_removeddefinelines += ($last - $first + 1);

            #   set output of new one
            $define_pri{$key} = $priority;
            $define_lines{$key} = "$linenoFirst:$linenoLast";
            &setOutput($linenoFirst, $linenoLast, 'take');
            print "    => $linenoFirst - $linenoLast: take DEFINE (updated) <$key>\n" if $debug;
        }
        else {
            &setOutput($linenoFirst, $linenoLast, 'remove');
            print "    => $linenoFirst - $linenoLast: remove DEFINE\n" if $debug;
            $stat_removeddefines++;
            $stat_removeddefinelines += ($linonoLast - $linonoFirst + 1);
        }
    }
    else {
        #   set output of new one
        $define_pri{$key} = $priority;
        $define_lines{$key} = "$linenoFirst:$linenoLast";
        &setOutput($linenoFirst, $linenoLast, 'take');
        print "    => $linenoFirst - $linenoLast: take DEFINE (first) <$key>\n" if $debug;
    }
}

sub setTarget {
    my ($linenoFirst, $linenoLast, $key) = @_;

    if ($target_pri{$key} ne '') {
        if ($target_pri{$key} <= $priority) {

            #   remove output of old one
            ($first, $last) = split(/:/, $target_lines{$key});
            &setOutput($first, $last, 'remove');
            print "    => $first - $last: remove\n" if $debug;
            $stat_removedtargets++;
            $stat_removedtargetlines += ($last - $first + 1);

            #   set output of new one
            $target_pri{$key} = $priority;
            $target_lines{$key} = "$linenoFirst:$linenoLast";
            &setOutput($linenoFirst, $linenoLast, 'take');
            print "    => $linenoFirst - $linenoLast: take TARGET (updated) <$key>\n" if $debug;
        }
        else {
            &setOutput($linenoFirst, $linenoLast, 'remove');
            print "    => $linenoFirst - $linenoLast: remove TARGET\n" if $debug;
            $stat_removedtargets++;
            $stat_removedtargetlines += ($linenoLast - $linenoFirst + 1);
        }
    }
    else {
        #   set output of new one
        $target_pri{$key} = $priority;
        $target_lines{$key} = "$linenoFirst:$linenoLast";
        &setOutput($linenoFirst, $linenoLast, 'take');
        print "    => $linenoFirst - $linenoLast: take TARGET (first) <$key>\n" if $debug;
    }
}

sub setVerbatim {
    my ($lineno) = @_;

    &setOutput($lineno, $lineno, 'take');
    print "    => $lineno: take VERBATIM\n" if $debug;
}

open(INPUT, "<$tmpfile");
$where = 'out';
loop: while (<INPUT>) {
    $linenoCur++;
    s|\n$||;
    print "$linenoCur: <$_>\n" if $debug;

    #
    #    process priority settings
    #
    if (m|^\.pri[ \t]*([+-]*\d+)[ \t]*$|) {
        &setPri($linenoCur, $1);
        next;
    }

    #
    #    process a definition
    #
    elsif ($where eq 'out' && m|^([a-zA-Z0-9_]+)[ \t]*=.*|) {
        #   first line of a define
        $key = $1;
        if (m|.*\\[ \t]*$|) {
            #   line will be continued
            $inputkey = $key;
            $linenoFirst = $linenoCur;
            $where = 'define';
            next;
        }
        else {
            #   define line end here 
            &setDefine($linenoCur, $linenoCur, $key);
            next;
        }
    }
    elsif ($where eq 'define') {
        #   continued line of a define
        if (m|.*\\[ \t]*$|) {
            #   line will be continued
            next;
        }
        else {
            #   define line end here 
            &setDefine($linenoFirst, $linenoCur, $inputkey);
            $where = 'out';
            next;
        }
    }


    #
    #    process a target
    #

    #   abc def: dsd \
    #   def haha \
    #   def haha
    elsif ($where eq 'out' && m|^([a-zA-Z0-9_\.-\/\$\(\)]+[ \t]*[a-zA-Z0-9_\.-\/\$\(\) ]*):.*|) {
        #   first line of target header
        $key = $1;
        $key =~ s| +$||;
        $key =~ s| +|:|g;
        if (m|.*\\[ \t]*$|) {
            #   line will be continued
            $inputkey = $key;
            $linenoFirst = $linenoCur;
            $where = 'targetheader1';
            next;
        }
        else {
            #   complete target header
            $inputkey = $key;
            $linenoFirst = $linenoCur;
            $where = 'targetbody';
            next;
        }
    }
    elsif ($where eq 'targetheader1') {
        #   continued line of a targetheader1
        if (m|.*\\[ \t]*$|) {
            #   line will be continued
            next;
        }
        else {
            #   complete target header
            $where = 'targetbody';
            next;
        }
    }

    #   abc def \
    #   abc def \
    #   def : haha
    elsif ($where eq 'out' && m|^([a-zA-Z0-9_\.-\/\$\(\)]+[ \t]*[a-zA-Z0-9_\.-\/\$\(\) ]*)\\[ \t]*$|) {
        #   first line of target header
        $key = $1;
        $key =~ s| +$||;
        $key =~ s| +|:|g;
        $inputkey = $key;
        $linenoFirst = $linenoCur;
        $where = 'targetheader2';
        next;
    }
    elsif ($where eq 'targetheader2' && m|^([a-zA-Z0-9_\.-\/\$\(\)]+[ \t]*[a-zA-Z0-9_\.-\/\$\(\) ]*)\\[ \t]*$|) {
        #   second line of target header
        $key = $1;
        $key =~ s| +$||;
        $key =~ s| +|:|g;
        $inputkey = $inputkey . ':' . $key;
        next;
    }
    elsif ($where eq 'targetheader2' && m|^([a-zA-Z0-9_\.-\/\$\(\)]+[ \t]*[a-zA-Z0-9_\.-\/\$\(\) ]*):.*|) {
        #   first line of target header's source dependecies
        $key = $1;
        $key =~ s| +$||;
        $key =~ s| +|:|g;
        $inputkey = $inputkey . ':' . $key;
        next;
    }
    elsif ($where eq 'targetheader2') {
        #   continued line of a targetheader2
        if (m|.*\\[ \t]*$|) {
            #   line will be continued
            next;
        }
        else {
            #   complete target header
            $where = 'targetbody';
            next;
        }
    }

    #  <TAB> xxxx
    #  <TAB> yyyy
    elsif ($where eq 'targetbody' && m|^\t.*|) {
        if (m|.*\\[ \t]*$|) {
            #   line will be continued
            $continued = 1;
            next;
        }
        else {
            #   line can be continued by more body lines
            $continued = 0;
            next;
        }
    }
    elsif ($where eq 'targetbody') {
        if ($continued == 1) {
            if (m|.*\\[ \t]*$|) {
                next;
            }
            else {
                $continued = 0;
                next;
            }
        }
        else {
            &setTarget($linenoFirst, $linenoCur - 1, $inputkey);
            $where = 'out';
            $linenoCur--;
            print "!REDO LAST LINE!\n" if $debug;
            redo;
        }
    }

    # 
    #   process any other things
    #
    elsif ($where eq 'out') {
        &setVerbatim($linenoCur);
    }
    else {
        print STDERR "WHAT'S THAT??\n";
    }

}

#
#   calculate more statistics
#
$stat_removedblanklines = 0;
$lineno = 0;
$wasnl  = 0;
seek(INPUT, 0, 0);
while ($lineno < $#outputlines) {
    $lineno++;
    $_ = <INPUT>;
    $what = $outputlines[$lineno];
    if ($what eq 'take') {
        if (m|^[ \t]*$|) {
            if ($wasnl == 1) {
                $stat_removedblanklines++;
            }
            $wasnl = 1;
        }
        else {
            $wasnl = 0;
        }
    }
}

#
#   now really process the inputfile...
#
seek(INPUT, 0, 0);
unlink($outputfile);
open(OUTPUT, ">$outputfile");

@pwinfo   = getpwuid($<);
$username = $pwinfo[0];
$realname = $pwinfo[6];
$realname =~ s|^([^\,]+)\,.*$|\1|;
$hostname = `hostname`;
$hostname =~ s|\n$||;
$date     = &ctime;

print OUTPUT "# $outputfile -- generated automatically from ``$inputfile'' via smake(1)\n";
print OUTPUT "# by $username@$hostname ($realname) at $date.\n";
print OUTPUT "# CAUTION! DO NOT MANUALLY EDIT THIS FILE DIRECTLY!\n";
print OUTPUT "#\n";

$lines = sprintf("%5d", $stat_sourcelines);
print OUTPUT "#     $lines lines of source from $inputfile\n";
print OUTPUT "#   -------\n";
$total = $lines;

$lines = sprintf("%5d", $stat_includedlines - $stat_includedfiles);
print OUTPUT "#   + $lines lines expanded from $stat_includedfiles include files\n";
$total = $total + $lines;

$lines = sprintf("%5d", $stat_removeddefinelines);
print OUTPUT "#   - $lines lines of $stat_removeddefines removed defines\n";
$total = $total - $lines;

$lines = sprintf("%5d", $stat_removedtargetlines);
print OUTPUT "#   - $lines lines of $stat_removedtargets removed targets\n";
$total = $total - $lines;

$lines = sprintf("%5d", $stat_removedopt);
print OUTPUT "#   - $lines lines of removed .opt directivies\n";
$total = $total - $lines;

$lines = sprintf("%5d", $stat_removedpri);
print OUTPUT "#   - $lines lines of removed .pri directivies\n";
$total = $total - $lines;

$lines = sprintf("%5d", $stat_removedblanklines);
print OUTPUT "#   - $lines lines of removed blank lines\n";
$total = $total - $lines;

print OUTPUT "#   +    16 lines for this comment\n";
$total = $total + 16;

$total = sprintf("%5d", $total);
print OUTPUT "#   -------\n";
print OUTPUT "#   = $total lines of target code for this file\n";
print OUTPUT "\n";

$lineno = 0;
$wasnl = 0;
while ($lineno < $#outputlines) {
    $_ = <INPUT>;
    $lineno++;

    $what = $outputlines[$lineno];
    if ($what eq 'take') {
        if (m|^[ \t]*$|) {
            next if ($wasnl == 1);
            $wasnl = 1;
            print OUTPUT $_;
        }
        else {
            $wasnl = 0;
            print OUTPUT $_;
        }
    }
    elsif ($what eq 'remove') {
        next;
    }
    else {
        print STDERR "BAD\n";
    }
}
close(OUTPUT);
close(INPUT);


#
#   cleanup
#
unlink($tmpfile);

#
#   exit gracefully
#
exit $EX{'OK'};


#EOF#

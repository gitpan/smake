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
##  smake_misc.pl -- miscellaneous stuff
##


#
#   get dirname and basename of program
#
$prgpath = $0;
if ($prgpath =~ m|^[^/]+$|) {
    $prgpath = ".";
}
else {
    $prgpath =~ s|^(.*)/[^/]+$|\1|;
}
$prgname = $0;
$prgname =~ s|^.*/([^/]+)$|\1|;

#
#   define 4.4BSD exit codes
#
%EX = (
    'OK',     0,
    'USAGE', 64,
    'OSERR', 71,
    'IOERR', 74
);

#
#   common definitions
#
$default_includepath = ".:..:@includedir@";
$tmpdir = "/tmp";

#   Use this function to convert a time() output to a "SUN (13.03.94)"
#   representation.
#
#   Usage: $str = &givetime(time());
#
@dow = ( 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat' );
@moy = ( 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
         'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' );

sub ctime {
    my ($str);

    local($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) =
        localtime(time());
    $str = sprintf("%s %s %2d %02d:%02d:%02d 19%s%s", 
        $dow[$wday], $moy[$mon], $mday, $hour, $min, $sec, $year, 
        $isdst ? " DST" : "");
    return $str;
}

1;

#EOF#

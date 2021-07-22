#!/usr/bin/perl -Tw

# Copyright (C) July 2021 Mark Tompsett
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your
# option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
# for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program. If not, see http://www.gnu.org/licenses/.

# This perl file is designed to fix MS-Access' poor date formatting
# to simplify MySQL importing without errors in a Date/DateTime
# set of fields.
#
# It is called with the name of the not-quite MySQL sql file, and the
# name of the database being created in MySQL.
#
# DANGER: It overwrites the sql file referenced.
#
# This perl script is used by a bash script and in conjuction with
# another perl script to massage MS-Access data into MySQL data.
# They are all released under GPL v3.

use Modern::Perl;
use File::Slurp;
use Data::Dumper;
use Carp qw/croak/;

our $VERSION = '2.0';

if ( $#ARGV < 0 ) {
    croak 'Missing SQL file to fix.';
}
if ( $#ARGV < 1 ) {
    croak 'Missing MySQL Database to USE.';
}
my $sql_file;
if ( $ARGV[0] =~ /(.*[.]sql)/gxlsm ) {
    $sql_file = $1;
}
my $database_name = $ARGV[1];

print "Reading file...\n";
my $content = read_file($sql_file);
print "Processing file...\n";
print "Processing 2-digit years, unpadded months...\n";
$content =~ s/\"(\d)\/(\d\d)\/(\d\d)([\" ])/\"20$3-0$1-$2$4/gsxlm;
print "Processing 2-digit years, unpadded months, unpadded days...\n";
$content =~ s/\"(\d)\/(\d)\/(\d\d)([\" ])/\"20$3-0$1-0$2$4/gsxlm;
print "Processing 2-digit years, padded months...\n";
$content =~ s/\"(\d\d)\/(\d\d)\/(\d\d)([\" ])/\"20$3-$1-$2$4/gsxlm;
print "Processing 4-digit years, unpadded months...\n";
$content =~ s/\"(\d)\/(\d\d)\/(\d\d\d\d)([\" ])/\"$3-0$1-$2$4/gsxlm;
print "Processing 4-digit years, padded months...\n";
$content =~ s/\"(\d\d)\/(\d\d)\/(\d\d\d\d)([\" ])/\"$3-$1-$2$4/gsxlm;
print "Processing 4-digit years, unpadded months, unpadded days...\n";
$content =~ s/\"(\d)\/(\d)\/(\d\d\d\d)([\" ])/\"$3-0$1-0$2$4/gsxlm;
print "Processing 4-digit years, padded months, unpadded days...\n";
$content =~ s/\"(\d\d)\/(\d)\/(\d\d\d\d)([\" ])/\"$3-$1-0$2$4/gsxlm;
print "Processing 4-digit years, unpadded months, bad 2nd delimiter...\n";
$content =~ s/\"(\d)\/(\d\d)(\d\d\d\d)([\" ])/\"$3-0$1-$2$4/gsxlm;
print "Writing output to SQL file...\n";
my $success = open my $file_handle, '>', $sql_file;

if ( defined $file_handle && $success ) {
    print {$file_handle} "USE ${database_name};\n\n";
    print {$file_handle} "$content";
    my $is_closed = close $file_handle;
}

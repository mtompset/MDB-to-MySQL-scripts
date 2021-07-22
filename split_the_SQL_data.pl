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

# This perl file is designed to take the huge SQL export from mdb tools
# and split it into reasonable (<2MB) pieces.
#
# It is called with the name of SQL file to split, and the database being
# created in MySQL. It generates split SQL files from the single SQL file.
#
# This perl script is used by a bash script and in conjuction with
# another perl script to massage MS-Access data into MySQL data.
# They are all released under GPL v3.

use Modern::Perl;
use File::Slurp;
use Data::Dumper;
use List::Util qw/uniq/;
use Carp qw/croak/;
use Text::Trim qw/trim/;

our $VERSION = '2.0';

if ( $#ARGV < 0 ) {
    croak 'Missing the SQL file name to split.';
}

if ( $#ARGV < 1 ) {
    croak 'Missing the MySQL Database name';
}

my $sql_file;
if ( $ARGV[0] =~ /(.*[.]sql)/gxlsm ) {
    $sql_file = $1;
}

my $database_name = $ARGV[1];

print "Reading file...\n";
my $content  = read_file($sql_file);
my @contents = split /\n/xslm, $content;

my @table_names;
my @insert_statements = grep { /INSERT/xlsm } @contents;
print 'Found ', $#insert_statements, " insert statements.\n";
foreach my $insert_statement (@insert_statements) {
    if ( "$insert_statement" =~ /\`(.*?)\`/xlsm ) {
        push @table_names, $1;
    }
}

my @tables = uniq @table_names;

print "Determining sections for split...\n";
my %sections;
my $line;
my $table     = q{};
my $tablename = q{};
foreach my $line_number ( 0 .. $#contents ) {
    my $line = $contents[$line_number];
    if ( "$line" =~ /\`(.*?)\`/xlsm ) {
        $table     = $1;
        $tablename = $table;
        $tablename =~ s/[ ]/_/gslxm;
    }
    next if ( trim($tablename) eq q{} );
    $sections{$tablename}{'end'} = $line_number;
    if ( ( $sections{$tablename}{'start'} // 0 ) == 0 && $line =~ /$table/xlsm )
    {
        $sections{$tablename}{'start'} = $line_number;
    }
}

print "Writing out split files...\n";
for my $section ( sort keys %sections ) {
    next if $section eq q{};
    my $section_content = join "\n",
      @contents[ $sections{$section}{'start'} .. $sections{$section}{'end'} ];
    my $success = open my $file_handle, '>', "split_$section.sql";
    if ( defined $file_handle && $success ) {
        print {$file_handle} "USE \`${database_name}\`;\n\n";
        print {$file_handle} "$section_content";
        my $is_closed = close $file_handle;
    }
}

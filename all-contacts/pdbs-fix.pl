#!/usr/bin/perl

use strict;
use warnings;

use Cwd;
use English;
use FindBin qw($Bin);
use Getopt::Long qw(HelpMessage :config pass_through);
use lib "$Bin/../lib";
use Share::DirUtil qw(get_dirs);
use Share::FileUtil;
use File::Copy qw(move);

GetOptions("help|h" => sub { print HelpMessage(0) });

my $Project_Dir = $ARGV[0] or die "A PROJ* dir must be specified\n";
$Project_Dir =~ s/\/$//;    # Remove trailing slash if any
my ($Project_Number) = $Project_Dir =~ /(\d+$)/;

my $outfile = "fix_FAH-PDBs_$Project_Dir.log";
open(my $OUT, '>', $outfile);

my $project_path = "${\getcwd()}/$Project_Dir";
fix_all_pdbs($project_path);

close($OUT);

sub fix_all_pdbs {
    my ($project_path) = @_;
    chdir($project_path);

    my @run_dirs = get_dirs($project_path, '^RUN\d+$');
    if (scalar(@run_dirs) == 0) {
        print $OUT "[ERROR] No RUN* found\n";
        return;
    }

    foreach my $run_dir (@run_dirs) {
        chdir $run_dir;
        my $run_path = "$project_path/$run_dir";
        print $OUT "Working on $run_path...\n";

        my @clone_dirs = get_dirs("$run_path", '^CLONE\d+$');
        if (scalar(@clone_dirs) == 0) {
            print $OUT "[ERROR] No CLONE* found in $run_dir\n";
            next;
        }

        foreach my $clone_dir (@clone_dirs) {
            chdir $clone_dir;
            my $clone_path = "$project_path/$run_dir/$clone_dir";
            print $OUT "Working on $clone_path...\n";
            check_pdbs($clone_path);
            chdir "..";
        }

        chdir "..";
    }
}

sub check_pdbs {
    my ($clone_path) = @_;

    opendir(my $CLONE_PATH, $clone_path);
    my @pdbs = grep { /\.pdb/i } readdir($CLONE_PATH);
    closedir($CLONE_PATH);

    if   (scalar(@pdbs) == 0) { print $OUT "[ERROR] No .pdb files found\n"; }
    else                      { print $OUT "Found ${\scalar(@pdbs)} PDBs\n"; }

    foreach my $pdb (@pdbs) {
        my $expected_time = get_time_from_pdb_filename($pdb);
        my $pdb_fix_result = fix_pdb($pdb, $expected_time);
        print $OUT "$pdb_fix_result\n";
    }
}

sub fix_pdb {

    # Fix PDB file
    # by looking for wrong time stamps and zero filesize

    my ($pdb_filename, $expected_time) = @_;
    if (!Share::FileUtil::file_ok($pdb_filename)) {
        return "[ERROR] $Share::FileUtil::File_Ok_Message";
    }

    my $pdb_time_from_content = get_time_from_pdb_content($pdb_filename);
    if ($pdb_time_from_content != $expected_time) {
        my $content_time_to_frame = $pdb_time_from_content / 100;
        chomp(my @filename_split = split(/_f/, $pdb_filename));
        my $pdb_prefix     = $filename_split[0];
        my $pdb_fix_rename = "$pdb_prefix" . "_f$content_time_to_frame.pdb";
        move $pdb_filename, $pdb_fix_rename;
        return
"Renamed $pdb_filename -> $pdb_fix_rename: time_from_content(within file)=$pdb_time_from_content, expected_time(filename)=$expected_time";
    }

    return "$pdb_filename created successfully!";
}

sub get_time_from_pdb_content {
    my ($pdb_filename) = @_;

    chomp(my $title_line = `head $pdb_filename | grep TITLE`);
    chomp(my @fields = split(/t=/, $title_line));
    my $time_in_ps = int($fields[1]);
    return $time_in_ps;
}

sub get_time_from_pdb_filename {
    my ($pdb_filename) = @_;
    $pdb_filename =~ s/\.pdb//;
    chomp(my @fields = split(/_f/, $pdb_filename));
    my $time_in_ps = int($fields[1]) * 100;
    return $time_in_ps;
}

=head1 NAME

pdbs-fix.pl - "Fix" the PDBs from duplicate time points generated by a GROMACS bug

=head1 SYNOPSIS

pdbs-fix.pl  -h

pdbs-fix.pl <project_dir>

Run this script in the location of the F@H PROJ* directories.
After running, grep resulting log file (fix_FAH-PDBs_PROJ*.log)
for "ERROR" to look for runtime errors.

=over

=item -h, --help

Print this help message.

=back

=cut
